# frozen_string_literal: true

module Ingestion
  # The HO §14 ingestion contract, in order:
  #
  #   receive → authenticate source → calculate identity/hash
  #           → insert RawEnvelope if new → enqueue normalization through outbox
  #
  # "Retries must not create duplicate canonical data. Database constraints are
  # the final authority." So idempotency here rests on the unique index over
  # (organization, source, source_record_id, source_record_version), not on a
  # check-then-insert — under concurrent delivery that race is exactly what the
  # constraint exists to lose.
  #
  # The payload is written to object storage BEFORE the row is inserted. If the
  # insert then loses the idempotency race, we have an orphaned object rather
  # than a row pointing at bytes that were never stored. Content-addressed keys
  # make that orphan harmless: the same bytes always land on the same key, so
  # the winning row already references it.
  class Receive
    Result = Struct.new(:envelope, :created, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(source:, payload:, source_record_id:, source_record_version: nil,
                   content_type: "application/json", observed_at: nil,
                   source_modified_at: nil, subject: nil, metadata: {},
                   adapter_key: "synthetic_json", adapter_version: "1",
                   store: Storage::RawPayloadStore.instance)
      @source = source
      @payload = payload
      @source_record_id = source_record_id.to_s
      @source_record_version = source_record_version
      @content_type = content_type
      @observed_at = observed_at
      @source_modified_at = source_modified_at
      @subject = subject
      @metadata = metadata
      @adapter_key = adapter_key
      @adapter_version = adapter_version
      @store = store
    end

    def call
      authenticate_source!

      existing = find_existing
      return Result.new(envelope: existing, created: false) if existing

      stored = @store.write(
        organization_id: source.organization_id,
        payload: payload,
        content_type: content_type
      )

      insert_envelope(stored)
    rescue ActiveRecord::RecordNotUnique
      # Lost the idempotency race with a concurrent delivery of the same
      # record. The winner is authoritative; adopt it. This is what makes
      # at-least-once delivery (S2C-020) safe.
      found = find_existing
      raise if found.nil?

      Result.new(envelope: found, created: false)
    end

    private

    attr_reader :source, :payload, :source_record_id, :source_record_version,
                :content_type, :observed_at, :source_modified_at, :subject,
                :metadata, :adapter_key, :adapter_version

    def authenticate_source!
      raise ArgumentError, "source is required" if source.nil?
      raise ArgumentError, "source #{source.key} is not active" unless source.active?
    end

    def find_existing
      RawEnvelope.where(
        organization_id: source.organization_id,
        source_id: source.id,
        source_record_id: source_record_id,
        source_record_version: source_record_version
      ).first
    end

    def insert_envelope(stored)
      envelope = nil

      # The envelope row and its outbox event commit together (HO §48,
      # S2C-021), so a normalization job can never be enqueued for evidence
      # that was rolled back, nor evidence stored with no downstream intent.
      ActiveRecord::Base.transaction(requires_new: true) do
        envelope = RawEnvelope.create!(
          organization_id: source.organization_id,
          source: source,
          subject: subject,
          source_record_id: source_record_id,
          source_record_version: source_record_version,
          content_type: content_type,
          object_key: stored[:object_key],
          content_hash: stored[:content_hash],
          observed_at: observed_at,
          source_modified_at: source_modified_at,
          received_at: Time.current,
          adapter_key: adapter_key,
          adapter_version: adapter_version,
          metadata: metadata
        )

        Outbox.publish(
          organization: source.organization,
          aggregate: envelope,
          event_type: "ingestion.envelope_received",
          # IDs only. CLAUDE.md forbids payloads in job arguments, and the
          # dispatcher passes only the event id onward anyway.
          payload: { "raw_envelope_id" => envelope.id, "source_key" => source.key }
        )
      end

      source.record_success!
      Result.new(envelope: envelope, created: true)
    end
  end
end
