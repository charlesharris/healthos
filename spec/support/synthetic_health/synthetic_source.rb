# frozen_string_literal: true

require_relative "decimal"
require_relative "fixtures"

module SyntheticHealth
  # Where a generated reading claims to have come from (SC §10–11).
  #
  # A source is not just a label. It carries the two things that make
  # instrumentation analysable rather than incidental:
  #
  #   * `calibration_offset` — a systematic bias this instrument adds to the
  #     recorded number. Applied OUTSIDE the biological process, so a
  #     source-switch scenario can prove that the latent series is unchanged
  #     while the recorded series moves (STAT-007/008/009).
  #   * `extra_noise_scale` — additional dispersion, for the "new device is
  #     noisier" case.
  #
  # Both may be a scalar (all dimensions) or a Hash keyed by semantic key.
  class SyntheticSource
    # Mirrors Source::SOURCE_TYPES and the observations.recording_method
    # CHECK constraint. Duplicated so the harness stays loadable without
    # Rails; cross-checked in the harness spec when Rails is loaded.
    SOURCE_TYPES = %w[synthetic csv_import customer_api fhir device_cloud rpm_vendor manual].freeze
    RECORDING_METHODS = %w[
      device_automatic device_manual_transcription manual_entry
      clinician_entered imported_batch unknown
    ].freeze

    attr_reader :key, :source_type, :device_key, :recording_method, :measurement_protocol,
      :calibration_offset, :extra_noise_scale, :source_family

    def initialize(key:,
                   source_type: "synthetic",
                   device_key: nil,
                   recording_method: "device_automatic",
                   measurement_protocol: nil,
                   calibration_offset: 0,
                   extra_noise_scale: 0,
                   source_family: nil)
      validate_inclusion!(:source_type, source_type, SOURCE_TYPES)
      validate_inclusion!(:recording_method, recording_method, RECORDING_METHODS)

      @key = key
      @source_type = source_type
      @device_key = device_key
      @recording_method = recording_method
      @measurement_protocol = measurement_protocol
      @calibration_offset = normalize_numeric(calibration_offset)
      @extra_noise_scale = normalize_numeric(extra_noise_scale)
      @source_family = source_family || key
      freeze
    end

    # --- NON-CLINICAL presets ---------------------------------------------

    def self.home_cuff(key: "src_home_cuff", device_key: "dev_home_cuff_a", **options)
      new(
        key: key, source_type: "device_cloud", device_key: device_key,
        recording_method: "device_automatic", measurement_protocol: "seated_rest_5min",
        source_family: "home_bp_cuff", **options
      )
    end

    # A second cuff with a calibration bias. Same measurement, different
    # number.
    def self.replacement_cuff(key: "src_replacement_cuff",
                              device_key: "dev_replacement_cuff_b",
                              calibration_offset: Fixtures::CUFF_OFFSET,
                              **options)
      new(
        key: key, source_type: "device_cloud", device_key: device_key,
        recording_method: "device_automatic", measurement_protocol: "seated_rest_5min",
        source_family: "home_bp_cuff", calibration_offset: calibration_offset, **options
      )
    end

    # Hand-typed readings: a different source family, noisier, and prone to
    # `manual_entry_absent` rather than `device_not_reporting`.
    def self.manual_entry(key: "src_manual_entry", **options)
      new(
        key: key, source_type: "manual", device_key: nil,
        recording_method: "manual_entry", measurement_protocol: "self_reported",
        source_family: "manual_entry", extra_noise_scale: 2, **options
      )
    end

    def self.clinic(key: "src_clinic", **options)
      new(
        key: key, source_type: "fhir", device_key: "dev_clinic_cuff",
        recording_method: "clinician_entered", measurement_protocol: "clinic_visit",
        source_family: "clinic", **options
      )
    end

    def offset_for(semantic_key)
      lookup(@calibration_offset, semantic_key)
    end

    def extra_noise_for(semantic_key)
      lookup(@extra_noise_scale, semantic_key)
    end

    def to_h
      {
        key: @key, source_type: @source_type, device_key: @device_key,
        recording_method: @recording_method, measurement_protocol: @measurement_protocol,
        source_family: @source_family,
        calibration_offset: describe(@calibration_offset),
        extra_noise_scale: describe(@extra_noise_scale)
      }
    end

    private

    def lookup(setting, semantic_key)
      value = setting.is_a?(Hash) ? setting.fetch(semantic_key, Decimal.zero) : setting
      Decimal.cast(value)
    end

    def normalize_numeric(value)
      return value.transform_values { |v| Decimal.cast(v) }.freeze if value.is_a?(Hash)

      Decimal.cast(value)
    end

    def describe(value)
      return value.transform_values(&:to_s) if value.is_a?(Hash)

      value.to_s("F")
    end

    def validate_inclusion!(field, value, allowed)
      return if allowed.include?(value)

      raise ArgumentError, "#{field} #{value.inspect} is not one of #{allowed.join(', ')}"
    end
  end
end
