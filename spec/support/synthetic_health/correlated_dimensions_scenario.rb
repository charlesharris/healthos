# frozen_string_literal: true

require_relative "fixtures"
require_relative "scenario"

module SyntheticHealth
  # Correlated Difference families (HO §100–101, SC §49–50, STAT-033/034).
  #
  # One cuff record yields systolic, diastolic and pulse. The engine will
  # additionally derive a daily summary and a variability metric from the same
  # records. When the subject's blood pressure steps up, several of those move
  # together — and they are not several discoveries. They are one finding seen
  # from several angles, and presenting them as mutual corroboration
  # exaggerates the evidence.
  #
  # This scenario generates exactly that situation, with the causal structure
  # stated explicitly in ground truth:
  #
  #   same_family              ONE injected cause; systolic and diastolic both
  #                            move because they share it. Redundant, not
  #                            confirmatory (STAT-033).
  #   with_independent_support ONE cause in the blood_pressure family, plus a
  #                            SEPARATE cause in the heart_rate family. Two
  #                            genuinely independent evidence families, which
  #                            may raise a Finding by at most one level
  #                            (STAT-034).
  #
  # Distinguishing those two cases is the entire test. The harness makes the
  # difference structural: in `same_family` there is exactly one Effect whose
  # `cause` is shared by two dimensions; in `with_independent_support` there
  # are two Effects with different causes and different semantic families.
  class CorrelatedDimensionsScenario < Scenario
    SHARED_CAUSE = "single underlying blood-pressure movement"
    INDEPENDENT_CAUSE = "separate heart-rate movement"

    class << self
      # Systolic and diastolic move from one shared cause. Pulse is generated
      # too, and deliberately does NOT move — so a spec can check the engine
      # does not manufacture support from a dimension that stayed put.
      def same_family(seed:,
                      magnitude: Fixtures::LEVEL_SHIFT,
                      coupling: Fixtures::DIASTOLIC_COUPLING,
                      **options)
        magnitude = Decimal.cast(magnitude)
        coupled = Decimal.round(magnitude * Decimal.cast(coupling))

        assemble(
          family: :correlated_families,
          seed: seed,
          shifts: {
            Dimensions::SYSTOLIC.semantic_key => magnitude,
            Dimensions::DIASTOLIC.semantic_key => coupled
          },
          effects: [
            family_effect(Dimensions::SYSTOLIC, magnitude, SHARED_CAUSE),
            family_effect(Dimensions::DIASTOLIC, coupled, SHARED_CAUSE)
          ],
          confounders: [ redundancy_confounder(coupling) ],
          notes: [
            "systolic and diastolic share one cause: correlated, not independent support (STAT-033)",
            "pulse is generated with no injected effect"
          ],
          **options
        )
      end

      # Adds a genuinely separate cause in a different semantic family.
      def with_independent_support(seed:,
                                   magnitude: Fixtures::LEVEL_SHIFT,
                                   coupling: Fixtures::DIASTOLIC_COUPLING,
                                   pulse_magnitude: 9,
                                   **options)
        magnitude = Decimal.cast(magnitude)
        coupled = Decimal.round(magnitude * Decimal.cast(coupling))
        pulse_shift = Decimal.cast(pulse_magnitude)

        assemble(
          family: :correlated_families_with_independent_support,
          seed: seed,
          shifts: {
            Dimensions::SYSTOLIC.semantic_key => magnitude,
            Dimensions::DIASTOLIC.semantic_key => coupled,
            Dimensions::PULSE.semantic_key => pulse_shift
          },
          effects: [
            family_effect(Dimensions::SYSTOLIC, magnitude, SHARED_CAUSE),
            family_effect(Dimensions::DIASTOLIC, coupled, SHARED_CAUSE),
            family_effect(Dimensions::PULSE, pulse_shift, INDEPENDENT_CAUSE)
          ],
          confounders: [ redundancy_confounder(coupling) ],
          notes: [
            "two independent causes in two semantic families; may raise a Finding at most one level (STAT-034)"
          ],
          **options
        )
      end

      private

      def family_effect(dimension, magnitude, cause)
        Effect.new(
          kind: :level_shift,
          semantic_key: dimension.semantic_key,
          magnitude: magnitude,
          unit: dimension.unit,
          direction: magnitude.negative? ? :decrease : :increase,
          phase: :affected,
          cause: cause,
          details: dimension.families
        )
      end

      # Not an artifact in the instrumentation sense, but the same category of
      # problem: structure in the data that inflates apparent evidence if
      # taken at face value.
      def redundancy_confounder(coupling)
        Confounder.new(
          kind: :correlated_dimensions,
          semantic_keys: [ Dimensions::SYSTOLIC.semantic_key, Dimensions::DIASTOLIC.semantic_key ],
          details: {
            shared_semantic_family: Dimensions::SYSTOLIC.semantic_family,
            shared_derivation_family: Dimensions::SYSTOLIC.derivation_family,
            diastolic_coupling: Decimal.cast(coupling).to_s("F"),
            derived_dimensions_expected_to_be_redundant: Dimensions::DERIVED_FROM_BLOOD_PRESSURE,
            note: "the harness emits raw readings only; derived summaries are the engine's own output " \
                  "and share these families"
          }
        )
      end

      def assemble(family:, seed:, shifts:, effects:, confounders:, notes:, dimensions: nil, **options)
        dimensions ||= Dimensions::BLOOD_PRESSURE_GROUP

        processes = dimensions.to_h do |dimension|
          components = [
            ValueProcess::Level.new(value: dimension.base_level_decimal),
            ValueProcess::WhiteNoise.new(scale: dimension.noise_scale_decimal)
          ]
          shift = shifts[dimension.semantic_key]
          components << ValueProcess::LevelShift.new(magnitude: shift) if shift

          [ dimension.semantic_key, ValueProcess.new(components) ]
        end

        new(
          family: family,
          seed: seed,
          dimensions: dimensions,
          processes: processes,
          effects: effects,
          confounders: confounders,
          notes: notes,
          **options
        )
      end
    end

    # Readings taken at the same opportunity share a group key: one cuff
    # inflation is ONE analytical unit, not three (SC §5, STAT-005).
    def grouped_readings
      readings.group_by(&:group_key)
    end

    def semantic_families
      dimensions.to_h { |dimension| [ dimension.semantic_key, dimension.semantic_family ] }
    end
  end
end
