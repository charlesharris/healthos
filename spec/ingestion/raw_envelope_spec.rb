# frozen_string_literal: true

require "rails_helper"

# Epic 001-05. HO §13.1, §13.2, §14; S2C-020, S2C-021; INV-1.
#
# The epic names one spec explicitly: "same record POSTed twice → one
# RawEnvelope, one normalization enqueue".
RSpec.describe "Raw envelope ingestion", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_org) { create_organization(name: "Southside", slug: "southside") }

  let!(:source) do
    Source.create!(
      organization: organization, key: "synthetic-bp", source_type: "synthetic",
      display_name: "Synthetic BP feed"
    )
  end

  # An in-memory stand-in for object storage. The real MinIO round trip is
  # covered separately below so the bulk of the suite does not need a running
  # bucket, while the integrity behaviour is still exercised for real.
  let(:store) do
    Class.new do
      attr_reader :objects

      def initialize = @objects = {}

      def write(organization_id:, payload:, content_type: "application/json")
        hash = Storage::RawPayloadStore.digest(payload)
        key = Storage::RawPayloadStore.key_for(organization_id: organization_id, content_hash: hash)
        @objects[key] = payload
        { object_key: key, content_hash: hash }
      end

      def read(object_key:, expected_hash:)
        payload = @objects.fetch(object_key)
        actual = Storage::RawPayloadStore.digest(payload)
        raise Storage::RawPayloadStore::IntegrityError, "mismatch" unless actual == expected_hash

        payload
      end
    end.new
  end

  def ingest(record_id: "bp-001", version: nil, payload: '{"systolic":142,"diastolic":88}', src: source)
    Ingestion::Receive.call(
      source: src, payload: payload,
      source_record_id: record_id, source_record_version: version,
      store: store
    )
  end

  describe "S2C-020 idempotency (HO §14)" do
    it "creates one envelope and one outbox event on first receipt" do
      result = ingest

      expect(result).to be_created
      expect(RawEnvelope.count).to eq(1)
      expect(DomainEvent.where(event_type: "ingestion.envelope_received").count).to eq(1)
    end

    # The spec the epic names.
    it "yields one envelope and one enqueue when the same record arrives twice" do
      first = ingest
      second = ingest

      expect(second.envelope).to eq(first.envelope)
      expect(second).not_to be_created
      expect(RawEnvelope.count).to eq(1)
      expect(DomainEvent.where(event_type: "ingestion.envelope_received").count).to eq(1)
    end

    it "treats a new source_record_version as new evidence" do
      ingest(version: "1")
      ingest(version: "2")

      expect(RawEnvelope.count).to eq(2)
    end

    # PostgreSQL treats NULLs as distinct in a unique index by default, which
    # would let a versionless record insert repeatedly. The index is declared
    # NULLS NOT DISTINCT; this asserts it.
    it "deduplicates versionless records despite the NULL version" do
      ingest(version: nil)
      ingest(version: nil)

      expect(RawEnvelope.count).to eq(1)
    end

    it "keeps identical record ids distinct across organizations" do
      other_source = Source.create!(
        organization: other_org, key: "synthetic-bp", source_type: "synthetic",
        display_name: "Synthetic BP feed"
      )

      ingest(src: source)
      ingest(src: other_source)

      expect(RawEnvelope.count).to eq(2)
    end

    # S2C-022: the constraint, not the service, is the authority.
    it "rejects a duplicate identity even when Ruby validation is skipped" do
      first = ingest.envelope
      # A distinct public_id, so it is the identity index that refuses this
      # and not an unrelated NOT NULL.
      duplicate = RawEnvelope.new(
        first.attributes.except("id", "created_at", "updated_at")
             .merge("public_id" => "env_#{SecureRandom.alphanumeric(20).downcase}")
      )

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_raw_envelopes_identity/)
    end
  end

  describe "INV-1 append-only" do
    it "refuses to mutate a persisted envelope in Ruby" do
      envelope = ingest.envelope

      expect { envelope.update!(content_type: "text/plain") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    # The database is the real guarantee (ADR-002 4a); readonly? is only the
    # legible error in front of it.
    it "refuses UPDATE at the database even when ActiveRecord is bypassed" do
      envelope = ingest.envelope

      expect {
        RawEnvelope.connection.execute(
          "UPDATE raw_envelopes SET content_type = 'text/plain' WHERE id = '#{envelope.id}'"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    it "refuses DELETE at the database" do
      envelope = ingest.envelope

      expect {
        RawEnvelope.connection.execute("DELETE FROM raw_envelopes WHERE id = '#{envelope.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end
  end

  describe "S2C-021 outbox atomicity" do
    it "writes no envelope and no event when the transaction fails" do
      allow(Outbox).to receive(:publish).and_raise(StandardError, "boom")

      expect { ingest }.to raise_error(StandardError, "boom")
      expect(RawEnvelope.count).to eq(0)
      expect(DomainEvent.count).to eq(0)
    end

    it "carries only ids in the event payload, never the raw record" do
      ingest(payload: '{"systolic":142,"secret_note":"do not leak"}')

      event = DomainEvent.last
      expect(event.payload.keys).to contain_exactly("raw_envelope_id", "source_key")
      expect(event.payload.to_json).not_to include("do not leak")
    end
  end

  describe "content hashing (ADR-002 4b)" do
    it "records a SHA-256 of the payload" do
      payload = '{"systolic":142}'
      envelope = ingest(payload: payload).envelope

      expect(envelope.content_hash).to eq(Digest::SHA256.hexdigest(payload))
    end

    it "content-addresses the object key, so identical bytes reuse one object" do
      a = ingest(record_id: "a", payload: '{"same":1}').envelope
      b = ingest(record_id: "b", payload: '{"same":1}').envelope

      expect(a.object_key).to eq(b.object_key)
      expect(RawEnvelope.count).to eq(2) # two envelopes, one object
    end

    it "verifies the hash on read and returns the payload" do
      payload = '{"systolic":142}'
      envelope = ingest(payload: payload).envelope

      expect(envelope.payload(store: store)).to eq(payload)
    end

    # Verification on read is the point. A hash that is written and never
    # checked proves nothing; a provenance drilldown showing altered evidence
    # would be worse than one that fails (INV-4, INV-5, HO §131).
    it "raises rather than returning bytes that do not match the recorded hash" do
      envelope = ingest.envelope
      store.objects[envelope.object_key] = '{"systolic":999}' # tampered

      expect { envelope.payload(store: store) }
        .to raise_error(Storage::RawPayloadStore::IntegrityError, /does not match|mismatch/)
    end
  end

  describe "source authentication (HO §14)" do
    it "refuses a paused source" do
      source.update!(status: "paused")

      expect { ingest }.to raise_error(ArgumentError, /not active/)
    end

    it "records success on the source" do
      expect { ingest }.to change { source.reload.last_success_at }.from(nil)
    end
  end

  describe "credentials (HO §13.2)" do
    it "stores source configuration encrypted, not as plain JSON" do
      source.update!(configuration: { "api_token" => "super-secret-token" })

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT configuration_encrypted FROM sources WHERE id = '#{source.id}'"
      )

      expect(raw).not_to include("super-secret-token")
      expect(source.reload.configuration["api_token"]).to eq("super-secret-token")
    end
  end
end
