# frozen_string_literal: true

require_relative "decimal"
require_relative "fixtures"

module SyntheticHealth
  # What a generated dimension is: its semantic identity, its shape, and its
  # family metadata (SC §50).
  #
  # The families are not decoration. Redundancy handling (SC §49, STAT-033)
  # depends on knowing that systolic and diastolic are two summaries of one
  # cuff record rather than two discoveries, and the harness has to state that
  # explicitly in ground truth so an engine spec can assert the engine
  # respected it.
  DimensionSpec = Struct.new(
    :semantic_key,
    :semantic_version,
    :unit,
    :precision,
    :base_level,
    :noise_scale,
    :semantic_family,
    :source_family,
    :derivation_family,
    :aggregation,
    :expected_measurement,
    keyword_init: true
  ) do
    def base_level_decimal
      Decimal.cast(base_level)
    end

    def noise_scale_decimal
      Decimal.cast(noise_scale)
    end

    def round(value)
      Decimal.cast(value).round(precision)
    end

    def families
      { semantic_family: semantic_family, source_family: source_family, derivation_family: derivation_family }
    end

    def with(**overrides)
      self.class.new(**to_h.merge(overrides))
    end
  end

  # NON-CLINICAL dimension presets.
  #
  # The harness core is domain-neutral — TimelineBuilder and the scenarios
  # accept any DimensionSpec. These presets are hypertension-shaped fixtures
  # because that is the reference domain, and they mirror the semantic keys
  # and families declared in
  # `app/domain_packs/hypertension/semantics/blood_pressure.yml`. Everything
  # here would work identically for a post-op recovery or oncology dimension
  # with different keys and numbers.
  module Dimensions
    # Integer precision because a cuff reports whole mmHg. Generating
    # fractional millimetres would make the fixture less like the data the
    # engine actually receives.
    SYSTOLIC = DimensionSpec.new(
      semantic_key: "health.vital.blood_pressure.systolic",
      semantic_version: 1,
      unit: "mmHg",
      precision: 0,
      base_level: Fixtures::SYSTOLIC_BASE,
      noise_scale: Fixtures::SYSTOLIC_NOISE,
      semantic_family: "blood_pressure",
      source_family: "home_bp_cuff",
      derivation_family: "direct_measurement",
      aggregation: "median",
      expected_measurement: "daily_opportunity"
    ).freeze

    DIASTOLIC = DimensionSpec.new(
      semantic_key: "health.vital.blood_pressure.diastolic",
      semantic_version: 1,
      unit: "mmHg",
      precision: 0,
      base_level: Fixtures::DIASTOLIC_BASE,
      noise_scale: Fixtures::DIASTOLIC_NOISE,
      semantic_family: "blood_pressure",
      source_family: "home_bp_cuff",
      derivation_family: "direct_measurement",
      aggregation: "median",
      expected_measurement: "daily_opportunity"
    ).freeze

    # A different semantic family on purpose. Pulse moving alongside blood
    # pressure IS independent support and may raise a Finding by at most one
    # level (STAT-034) — which is only testable if the harness can generate a
    # genuinely separate injected cause.
    PULSE = DimensionSpec.new(
      semantic_key: "health.vital.pulse",
      semantic_version: 1,
      unit: "bpm",
      precision: 0,
      base_level: Fixtures::PULSE_BASE,
      noise_scale: Fixtures::PULSE_NOISE,
      semantic_family: "heart_rate",
      source_family: "home_bp_cuff",
      derivation_family: "direct_measurement",
      aggregation: "median",
      expected_measurement: "daily_opportunity"
    ).freeze

    BLOOD_PRESSURE_GROUP = [ SYSTOLIC, DIASTOLIC, PULSE ].freeze

    # Derived dimensions the engine computes from the raw readings above. The
    # harness does NOT emit them — a derived signal is the engine's output,
    # and generating it here would let a redundancy bug pass unnoticed. They
    # are named in ground truth so a correlated-families spec can assert which
    # dimensions are expected to be mutually redundant (SC §49).
    DERIVED_FROM_BLOOD_PRESSURE = %w[
      health.vital.blood_pressure.daily_summary
      health.vital.blood_pressure.variability
    ].freeze
  end
end
