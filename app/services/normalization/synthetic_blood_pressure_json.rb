# frozen_string_literal: true

module Normalization
  # Normalizer v1 for the synthetic BP JSON feed (epic 001-08).
  #
  # Expected payload:
  #
  #   {
  #     "subject_identifier": { "system": "mrn", "value": "MRN-001" },
  #     "recorded_at": "2026-03-15T14:00:00Z",
  #     "timezone_offset_minutes": -240,
  #     "systolic": 142, "diastolic": 88, "pulse": 68,
  #     "recording_method": "device_automatic",
  #     "measurement_protocol": "seated_rest_5min",
  #     "device_external_id": "cuff-1"
  #   }
  #
  # Emits one ObservationGroup with up to three observations, because a cuff
  # inflation is one measurement event — three observations from it are one
  # analytical unit, not three (SC §5, STAT-005).
  #
  # A reading present in the payload but null is NOT silently dropped: it
  # becomes an `invalid_measurement` observation carrying no value. Dropping it
  # would make the gap invisible, and an invisible gap is indistinguishable
  # from a measurement that was never expected — which is precisely the
  # collapse STAT-002 and STAT-010 forbid.
  class SyntheticBloodPressureJson < Normalizer
    KEY = "synthetic_bp_json"
    VERSION = 1

    GROUP_SEMANTIC_KEY = "health.vital.blood_pressure"

    COMPONENTS = {
      "systolic" => { key: "health.vital.blood_pressure.systolic", unit: "mmHg" },
      "diastolic" => { key: "health.vital.blood_pressure.diastolic", unit: "mmHg" },
      "pulse" => { key: "health.vital.pulse", unit: "bpm" }
    }.freeze

    def self.key = KEY
    def self.version = VERSION

    def call
      data = parse
      observed_at = parse_time(data["recorded_at"])

      observations = COMPONENTS.filter_map do |field, spec|
        next unless data.key?(field)

        build_observation(field, spec, data, observed_at)
      end

      raise InvalidPayload, "payload contains no recognized measurements" if observations.empty?

      group = GroupIntent.new(
        semantic_key: GROUP_SEMANTIC_KEY,
        semantic_version: 1,
        observed_at: observed_at,
        observations: observations
      )

      Result.new(
        groups: [ group ],
        observations: observations,
        subject_identifier: data["subject_identifier"]
      )
    end

    private

    def parse
      data = payload.is_a?(String) ? JSON.parse(payload) : payload
      raise InvalidPayload, "payload must be a JSON object" unless data.is_a?(Hash)
      raise InvalidPayload, "recorded_at is required" if data["recorded_at"].blank?

      data
    rescue JSON::ParserError => e
      raise InvalidPayload, "payload is not valid JSON: #{e.message}"
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) or raise InvalidPayload, "unparseable recorded_at: #{value.inspect}"
    end

    def build_observation(field, spec, data, observed_at)
      raw = data[field]
      definition = Definitions::Registry.fetch(spec[:key])

      if raw.nil?
        # Present but null — a reading that was attempted and did not produce
        # a value. Recorded, never dropped.
        return ObservationIntent.new(
          semantic_key: spec[:key], semantic_version: definition.version,
          value_numeric: nil, unit: nil, observed_at: observed_at,
          quality_state: "invalid_measurement",
          recording_method: data.fetch("recording_method", "unknown"),
          measurement_protocol: data["measurement_protocol"],
          timezone_offset_minutes: data["timezone_offset_minutes"],
          quality_flags: { "reason" => "null_in_source_payload" }
        )
      end

      numeric = BigDecimal(raw.to_s)

      ObservationIntent.new(
        semantic_key: spec[:key], semantic_version: definition.version,
        value_numeric: numeric, unit: spec[:unit], observed_at: observed_at,
        quality_state: "observed",
        recording_method: data.fetch("recording_method", "unknown"),
        measurement_protocol: data["measurement_protocol"],
        timezone_offset_minutes: data["timezone_offset_minutes"],
        quality_flags: {}
      )
    rescue ArgumentError, TypeError
      # Non-numeric where a number was expected. Same reasoning as null:
      # recorded as invalid rather than discarded.
      ObservationIntent.new(
        semantic_key: spec[:key], semantic_version: 1,
        value_numeric: nil, unit: nil, observed_at: observed_at,
        quality_state: "invalid_measurement",
        recording_method: data.fetch("recording_method", "unknown"),
        measurement_protocol: data["measurement_protocol"],
        timezone_offset_minutes: data["timezone_offset_minutes"],
        quality_flags: { "reason" => "non_numeric_value", "raw" => raw.to_s.truncate(40) }
      )
    end
  end
end
