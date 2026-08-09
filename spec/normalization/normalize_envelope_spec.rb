# frozen_string_literal: true

require "rails_helper"

# Epic 001-08. HO §21 (provenance), §96 (idempotency matrix), §155
# (reprocessing); INV-1, INV-2, INV-3, INV-6.
#
# The epic names two specs: re-running normalization creates no duplicate
# canonical rows, and every observation traces to its envelope.
RSpec.describe "Normalization", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP")
  end

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
        raise Storage::RawPayloadStore::IntegrityError, "does not match" unless actual == expected_hash

        payload
      end
    end.new
  end

  let(:bp_payload) do
    {
      subject_identifier: { system: "mrn", value: "MRN-001" },
      recorded_at: "2026-03-15T14:00:00Z",
      timezone_offset_minutes: -240,
      systolic: 142, diastolic: 88, pulse: 68,
      recording_method: "device_automatic",
      measurement_protocol: "seated_rest_5min"
    }.to_json
  end

  def ingest(payload: bp_payload, record_id: "bp-001")
    Ingestion::Receive.call(
      source: source, payload: payload, source_record_id: record_id, store: store
    ).envelope
  end

  def normalize(envelope) = Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)

  describe "mapping" do
    it "produces one group and three observations from one cuff inflation" do
      result = normalize(ingest)

      expect(result).to be_created
      expect(result.observations.size).to eq(3)
      expect(result.group).to be_present
      expect(result.observations.map(&:observation_group_id).uniq).to eq([ result.group.id ])
    end

    it "maps values, units and semantics correctly" do
      normalize(ingest)

      systolic = Observation.find_by(semantic_key: "health.vital.blood_pressure.systolic")
      expect(systolic.value_numeric).to eq(142)
      expect(systolic.unit).to eq("mmHg")
      expect(systolic.semantic_version).to eq(1)
      expect(systolic).to be_observed
    end

    it "resolves the subject from the payload identifier" do
      normalize(ingest)

      expect(Subject.count).to eq(1)
      expect(SubjectIdentifier.find_by(system: "mrn", value: "MRN-001")).to be_present
    end

    # A reading present but null is recorded as invalid, never dropped.
    # Dropping it would make the gap invisible, and an invisible gap is
    # indistinguishable from one that was never expected — the exact collapse
    # STAT-002 and STAT-010 forbid.
    it "records a null reading as invalid_measurement rather than dropping it" do
      payload = JSON.parse(bp_payload).merge("pulse" => nil).to_json
      normalize(ingest(payload: payload))

      pulse = Observation.find_by(semantic_key: "health.vital.pulse")
      expect(pulse.quality_state).to eq("invalid_measurement")
      expect(pulse.value_numeric).to be_nil
      expect(pulse.quality_flags["reason"]).to eq("null_in_source_payload")
    end

    it "records a non-numeric reading as invalid rather than coercing it" do
      payload = JSON.parse(bp_payload).merge("systolic" => "not a number").to_json
      normalize(ingest(payload: payload))

      systolic = Observation.find_by(semantic_key: "health.vital.blood_pressure.systolic")
      expect(systolic.quality_state).to eq("invalid_measurement")
      expect(systolic.value_numeric).to be_nil
    end

    it "omits a component absent from the payload entirely" do
      payload = JSON.parse(bp_payload).except("pulse").to_json
      normalize(ingest(payload: payload))

      # Absent from the source is not the same as present-but-null. The
      # expectation model in epic 002-01 decides whether this is a gap.
      expect(Observation.where(semantic_key: "health.vital.pulse")).to be_empty
      expect(Observation.count).to eq(2)
    end
  end

  # The epic's named spec.
  describe "HO §96 idempotency on RawEnvelope + normalizer version" do
    it "creates no duplicate canonical rows when re-run" do
      envelope = ingest
      first = normalize(envelope)
      second = normalize(envelope)

      expect(first).to be_created
      expect(second).not_to be_created
      expect(second.skipped_reason).to eq(:already_normalized)
      expect(Observation.count).to eq(3)
      expect(ObservationGroup.count).to eq(1)
    end

    it "is safe under a retried job" do
      envelope = ingest
      3.times { normalize(envelope) }

      expect(Observation.count).to eq(3)
    end

    # HO §155: reprocessing produces NEW artifacts beside the old, so a
    # historical analysis referencing v1 rows stays reproducible.
    it "produces a parallel set under a new normalizer version" do
      envelope = ingest
      normalize(envelope)

      v2 = Class.new(Normalization::SyntheticBloodPressureJson) do
        def self.key = "synthetic_bp_json"
        def self.version = 2
      end
      allow(Normalization::Normalizer).to receive(:for_adapter).and_return(v2)

      result = normalize(envelope)

      expect(result).to be_created
      expect(Observation.count).to eq(6)
      expect(Observation.where(normalizer_version: 1).count).to eq(3)
      expect(Observation.where(normalizer_version: 2).count).to eq(3)
    end
  end

  # The epic's other named spec.
  describe "INV-1/2/3 provenance" do
    it "traces every observation to its envelope" do
      envelope = ingest
      normalize(envelope)

      Observation.find_each do |observation|
        expect(observation.raw_envelope_id).to eq(envelope.id)
        expect(observation.provenance[:raw_envelope_id]).to eq(envelope.id)
      end
    end

    it "stamps the normalizer key and version on every row (INV-6)" do
      normalize(ingest)

      expect(Observation.pluck(:normalizer_key).uniq).to eq([ "synthetic_bp_json" ])
      expect(Observation.pluck(:normalizer_version).uniq).to eq([ 1 ])
    end

    it "reaches the stored payload from a canonical value" do
      envelope = ingest
      normalize(envelope)

      observation = Observation.first
      expect(observation.raw_envelope.payload(store: store)).to eq(bp_payload)
    end

    it "preserves the source timezone offset" do
      normalize(ingest)

      expect(Observation.pluck(:timezone_offset_minutes).uniq).to eq([ -240 ])
    end
  end

  describe "integrity (ADR-002 4b)" do
    # A payload that no longer matches its recorded hash must never become
    # canonical evidence.
    it "refuses to normalize a tampered payload" do
      envelope = ingest
      store.objects[envelope.object_key] = '{"systolic":999}'

      expect { normalize(envelope) }
        .to raise_error(Storage::RawPayloadStore::IntegrityError)
      expect(Observation.count).to eq(0)
    end
  end

  describe "S2C-021 outbox" do
    it "publishes telemetry.observation_created in the same transaction" do
      normalize(ingest)

      event = DomainEvent.find_by(event_type: "telemetry.observation_created")
      expect(event).to be_present
      expect(event.payload["observation_count"]).to eq(3)
    end

    it "writes no canonical rows when the transaction fails" do
      envelope = ingest
      allow(Outbox).to receive(:publish).and_raise(StandardError, "boom")

      expect { normalize(envelope) }.to raise_error(StandardError, "boom")
      expect(Observation.count).to eq(0)
      expect(ObservationGroup.count).to eq(0)
    end
  end

  describe "the outbox wiring" do
    it "registers the normalization job for ingestion.envelope_received" do
      expect(Outbox::Registry.job_for("ingestion.envelope_received"))
        .to eq(Normalization::NormalizeEnvelopeJob)
    end
  end
end
