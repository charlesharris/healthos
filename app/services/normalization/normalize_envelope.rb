# frozen_string_literal: true

module Normalization
  # Turns one RawEnvelope into canonical telemetry (HO §113
  # Normalization::NormalizeEnvelope).
  #
  # Idempotent on RawEnvelope + normalizer version (HO §96). The guarantee is
  # the unique index `index_observations_normalization_identity`, not a
  # check-then-insert — jobs are at-least-once (S2C-020), so the race is real.
  #
  # Reprocessing under a NEW normalizer version deliberately produces a new
  # set of rows beside the old ones rather than replacing them (HO §155:
  # "raw remains unchanged, old derived artifacts remain if referenced, new
  # artifacts get new versions").
  class NormalizeEnvelope
    Result = Struct.new(:observations, :group, :created, :skipped_reason, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(envelope:, store: Storage::RawPayloadStore.instance)
      @envelope = envelope
      @store = store
    end

    def call
      normalizer_class = Normalizer.for_adapter(envelope.adapter_key)

      if already_normalized?(normalizer_class)
        return Result.new(observations: existing_observations(normalizer_class), created: false,
                          skipped_reason: :already_normalized)
      end

      # Verified on read (ADR-002 4b): a payload that no longer matches its
      # recorded hash must not become canonical evidence.
      payload = @store.read(object_key: envelope.object_key, expected_hash: envelope.content_hash)
      result = normalizer_class.new(envelope: envelope, payload: payload).call

      subject = resolve_subject(result)
      persist(result, subject, normalizer_class)
    rescue ActiveRecord::RecordNotUnique
      # Lost the race with a concurrent normalization of the same envelope.
      Result.new(observations: existing_observations(Normalizer.for_adapter(envelope.adapter_key)),
                 created: false, skipped_reason: :concurrent)
    end

    private

    attr_reader :envelope

    def already_normalized?(normalizer_class)
      existing_observations(normalizer_class).exists?
    end

    def existing_observations(normalizer_class)
      Observation.where(raw_envelope_id: envelope.id, normalizer_version: normalizer_class.version)
    end

    # An envelope may arrive before we know whose it is (HO §13.1 allows a
    # null subject_id). Normalization is where identity is resolved, because
    # storing raw truth must never be blocked by our ability to interpret it.
    def resolve_subject(result)
      return envelope.subject if envelope.subject_id.present?

      identifier = result.subject_identifier
      raise Normalizer::InvalidPayload, "payload has no subject_identifier" if identifier.blank?

      Identity::ResolveSubject.call(
        organization: envelope.organization,
        system: identifier.fetch("system"),
        value: identifier.fetch("value"),
        source: envelope.source
      ).subject
    end

    def persist(result, subject, normalizer_class)
      observations = []
      group = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        intent = result.groups.first

        if intent
          group = ObservationGroup.create!(
            organization: envelope.organization, subject: subject,
            source: envelope.source, raw_envelope: envelope,
            semantic_key: intent.semantic_key, semantic_version: intent.semantic_version,
            observed_at: intent.observed_at
          )
        end

        observations = result.observations.map do |obs|
          Observation.create!(
            organization: envelope.organization, subject: subject,
            source: envelope.source, raw_envelope: envelope,
            observation_group: group, device: device_for(subject),
            source_record_id: envelope.source_record_id,
            semantic_key: obs.semantic_key, semantic_version: obs.semantic_version,
            value_numeric: obs.value_numeric, value_text: obs.value_text,
            value_code: obs.value_code, unit: obs.unit,
            observed_at: obs.observed_at,
            timezone_offset_minutes: obs.timezone_offset_minutes,
            quality_state: obs.quality_state, quality_flags: obs.quality_flags || {},
            recording_method: obs.recording_method || "unknown",
            measurement_protocol: obs.measurement_protocol,
            source_modified_at: envelope.source_modified_at,
            ingested_at: envelope.received_at,
            normalized_at: Time.current,
            normalizer_key: normalizer_class.key,
            normalizer_version: normalizer_class.version
          )
        end

        Outbox.publish(
          organization: envelope.organization, aggregate: envelope,
          event_type: "telemetry.observation_created",
          payload: {
            "raw_envelope_id" => envelope.id,
            "subject_id" => subject.id,
            "observation_count" => observations.size
          }
        )
      end

      Result.new(observations: observations, group: group, created: true)
    end

    def device_for(_subject)
      nil # Device attribution lands with the device-transition work in 002-05.
    end
  end
end
