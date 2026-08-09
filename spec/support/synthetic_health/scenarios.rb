# frozen_string_literal: true

require_relative "correlated_dimensions_scenario"
require_relative "source_switch_scenario"
require_relative "trajectory_scenario"

module SyntheticHealth
  # The scenario catalogue.
  #
  # `REQUIRED_FAMILIES` is the HO §100 list, verbatim. Engine specs iterate it
  # so that adding a statistical method cannot quietly skip a family: if the
  # engine can only be evaluated against three of the nine, that is visible.
  #
  # Everything is addressed by `(family, seed)`. Two calls with the same pair
  # produce byte-identical readings, in this process and in any other.
  module Scenarios
    # HO §100, in order.
    REQUIRED_FAMILIES = %i[
      null
      level_shift
      trend
      source_switch_artifact
      missingness_artifact
      sparse_outliers
      autocorrelation
      phase_drift
      correlated_families
    ].freeze

    # Families beyond the mandated nine, each supporting a specific HO §101
    # acceptance behaviour.
    ADDITIONAL_FAMILIES = %i[
      small_sample
      source_switch_with_biology
      correlated_families_with_independent_support
    ].freeze

    FAMILIES = (REQUIRED_FAMILIES + ADDITIONAL_FAMILIES).freeze

    BUILDERS = {
      null: ->(seed:, **options) { TrajectoryScenario.null(seed: seed, **options) },
      level_shift: ->(seed:, **options) { TrajectoryScenario.level_shift(seed: seed, **options) },
      trend: ->(seed:, **options) { TrajectoryScenario.trend(seed: seed, **options) },
      autocorrelation: ->(seed:, **options) { TrajectoryScenario.autocorrelation(seed: seed, **options) },
      phase_drift: ->(seed:, **options) { TrajectoryScenario.phase_drift(seed: seed, **options) },
      sparse_outliers: ->(seed:, **options) { TrajectoryScenario.sparse_outliers(seed: seed, **options) },
      missingness_artifact: ->(seed:, **options) { TrajectoryScenario.missingness_artifact(seed: seed, **options) },
      small_sample: ->(seed:, **options) { TrajectoryScenario.small_sample(seed: seed, **options) },
      source_switch_artifact: ->(seed:, **options) { SourceSwitchScenario.partial_switch(seed: seed, **options) },
      source_switch_with_biology: lambda { |seed:, **options|
        SourceSwitchScenario.with_biological_shift(seed: seed, **options)
      },
      correlated_families: ->(seed:, **options) { CorrelatedDimensionsScenario.same_family(seed: seed, **options) },
      correlated_families_with_independent_support: lambda { |seed:, **options|
        CorrelatedDimensionsScenario.with_independent_support(seed: seed, **options)
      }
    }.freeze

    module_function

    def build(family, seed:, **options)
      builder = BUILDERS[family.to_sym]
      raise ArgumentError, "unknown scenario family #{family.inspect}; known: #{FAMILIES.join(', ')}" unless builder

      builder.call(seed: seed, **options)
    end

    # Every family at one seed. The default sweep for engine acceptance specs.
    def all(seed:, families: FAMILIES, **options)
      families.map { |family| build(family, seed: seed, **options) }
    end

    def required(seed:, **options)
      all(seed: seed, families: REQUIRED_FAMILIES, **options)
    end

    # Families that inject no biological effect at all. Null-like data should
    # frequently produce "No reliable distinguishing pattern found"
    # (STAT-036, HO §102) — this is the set that claim is measured over.
    def without_injected_effect(seed:, **options)
      all(seed: seed, **options).reject { |scenario| scenario.truth.biological_effect_present? }
    end
  end
end
