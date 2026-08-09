# frozen_string_literal: true

require_relative "fixtures"
require_relative "scenario"

module SyntheticHealth
  # Single-dimension trajectory families (HO §100).
  #
  # Covers the shapes a within-subject window comparison has to tell apart:
  #
  #   null                 nothing happened
  #   level_shift          a real, sustained step
  #   trend                a real, gradual drift
  #   autocorrelation      nothing happened, but consecutive readings are
  #                        strongly correlated, so naive methods see evidence
  #                        that is not there
  #   phase_drift          nothing changed, but a slow cycle is sampled at two
  #                        different phases
  #   sparse_outliers      nothing happened, plus a few contaminated readings
  #   missingness_artifact nothing happened, but the subject largely stopped
  #                        measuring
  #   small_sample         a real shift in a window too short to support a
  #                        longitudinal claim
  #
  # Five of those eight inject nothing at all. That balance is intentional:
  # "No reliable distinguishing pattern found" is a successful output
  # (STAT-036), and an acceptance instrument that mostly generates real
  # effects would never find out whether the engine can say so.
  class TrajectoryScenario < Scenario
    NO_EFFECT_NOTE = "no biological effect injected; any apparent difference is a property of the confounder"

    class << self
      def null(seed:, **options)
        assemble(family: :null, seed: seed, **options)
      end

      def level_shift(seed:, magnitude: Fixtures::LEVEL_SHIFT, **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)
        magnitude = Decimal.cast(magnitude)

        assemble(
          family: :level_shift,
          seed: seed,
          extra_components: [ ValueProcess::LevelShift.new(magnitude: magnitude) ],
          effects: [ level_shift_effect(dimension, magnitude) ],
          **options
        )
      end

      def trend(seed:, slope_per_day: Fixtures::TREND_SLOPE_PER_DAY, **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)
        window = options.fetch(:window, AnalysisWindow.default)
        slope = Decimal.cast(slope_per_day)
        component = ValueProcess::LinearTrend.new(slope_per_day: slope)

        assemble(
          family: :trend,
          seed: seed,
          extra_components: [ component ],
          effects: [ trend_effect(dimension, slope, component.total_change_over(window.affected_days)) ],
          window: window,
          **options.except(:window)
        )
      end

      # Stationary, but strongly autocorrelated (SC §27).
      def autocorrelation(seed:, phi: Fixtures::AR1_PHI, innovation_scale: Fixtures::AR1_INNOVATION_SCALE, **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)

        assemble(
          family: :autocorrelation,
          seed: seed,
          noise: :none,
          extra_components: [ ValueProcess::Ar1Noise.new(phi: phi, innovation_scale: innovation_scale) ],
          confounders: [
            Confounder.new(
              kind: :autocorrelation,
              semantic_keys: [ dimension.semantic_key ],
              details: {
                phi: Decimal.cast(phi).to_s("F"),
                innovation_scale: Decimal.cast(innovation_scale).to_s("F"),
                note: "consecutive readings are not independent observations (STAT-004/005)"
              }
            )
          ],
          notes: [ NO_EFFECT_NOTE ],
          **options
        )
      end

      # An unchanged cyclic process sampled at two phases (SC §62–63).
      def phase_drift(seed:,
                      amplitude: Fixtures::SEASONAL_AMPLITUDE,
                      period_days: Fixtures::SEASONAL_PERIOD_DAYS,
                      phase_offset_days: 0,
                      **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)

        assemble(
          family: :phase_drift,
          seed: seed,
          extra_components: [
            ValueProcess::SeasonalWave.new(
              amplitude: amplitude, period_days: period_days, phase_offset_days: phase_offset_days
            )
          ],
          confounders: [
            Confounder.new(
              kind: :phase_drift,
              semantic_keys: [ dimension.semantic_key ],
              details: {
                amplitude: Decimal.cast(amplitude).to_s("F"),
                period_days: period_days,
                phase_offset_days: phase_offset_days,
                note: "cyclic, not sustained; realized window difference is in truth.latent_median_delta"
              }
            )
          ],
          notes: [ NO_EFFECT_NOTE ],
          **options
        )
      end

      # Ordinary data plus a few implausible readings.
      def sparse_outliers(seed:,
                          count: Fixtures::OUTLIER_COUNT,
                          magnitude: Fixtures::OUTLIER_MAGNITUDE,
                          sign: :both,
                          **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)

        assemble(
          family: :sparse_outliers,
          seed: seed,
          extra_components: [ ValueProcess::Outliers.new(count: count, magnitude: magnitude, sign: sign) ],
          confounders: [
            Confounder.new(
              kind: :sparse_outliers,
              semantic_keys: [ dimension.semantic_key ],
              details: {
                count: count,
                magnitude: Decimal.cast(magnitude).to_s("F"),
                note: "contaminated indices are in truth.process; Readings carry no marker for them"
              }
            )
          ],
          notes: [ NO_EFFECT_NOTE ],
          **options
        )
      end

      # Unchanged biology, collapsed measurement behaviour (SC §16, STAT-003).
      def missingness_artifact(seed:,
                               baseline_rate: Fixtures::ROUTINE_MISSING_RATE,
                               affected_rate: Fixtures::COLLAPSED_MISSING_RATE,
                               **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)
        pattern = MissingnessPattern.by_phase(
          rates: { baseline: baseline_rate, gap: baseline_rate, affected: affected_rate }
        )

        assemble(
          family: :missingness_artifact,
          seed: seed,
          missingness: pattern,
          confounders: [
            Confounder.new(
              kind: :missingness_collapse,
              semantic_keys: [ dimension.semantic_key ],
              details: {
                baseline_dropout_rate: Decimal.cast(baseline_rate).to_s("F"),
                affected_dropout_rate: Decimal.cast(affected_rate).to_s("F"),
                note: "realized completeness on both sides is in truth.realized (STAT-011/021)"
              }
            )
          ],
          notes: [ NO_EFFECT_NOTE, "measurement behaviour is itself analyzable data (STAT-003)" ],
          **options.except(:missingness)
        )
      end

      # A real shift, in a window too short to support a longitudinal claim.
      # HO §101: the Case may exist while the Comparison declines to speak.
      def small_sample(seed:, magnitude: Fixtures::LEVEL_SHIFT, window: AnalysisWindow.sparse, **options)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)
        magnitude = Decimal.cast(magnitude)

        assemble(
          family: :small_sample,
          seed: seed,
          window: window,
          extra_components: [ ValueProcess::LevelShift.new(magnitude: magnitude) ],
          effects: [ level_shift_effect(dimension, magnitude) ],
          notes: [ "a real effect in a window too short to support a longitudinal claim (SC §23)" ],
          **options.except(:window)
        )
      end

      private

      def level_shift_effect(dimension, magnitude)
        Effect.new(
          kind: :level_shift,
          semantic_key: dimension.semantic_key,
          magnitude: magnitude,
          unit: dimension.unit,
          direction: magnitude.negative? ? :decrease : :increase,
          phase: :affected,
          cause: "injected sustained level shift",
          details: {}
        )
      end

      def trend_effect(dimension, slope, total_change)
        Effect.new(
          kind: :trend,
          semantic_key: dimension.semantic_key,
          magnitude: total_change,
          unit: dimension.unit,
          direction: slope.negative? ? :decrease : :increase,
          phase: :affected,
          slope_per_day: slope,
          cause: "injected linear trend",
          details: { magnitude_is: "total drift accumulated across the affected window" }
        )
      end

      def assemble(family:,
                   seed:,
                   dimension: Dimensions::SYSTOLIC,
                   noise: :white,
                   extra_components: [],
                   effects: [],
                   confounders: [],
                   notes: [],
                   **options)
        components = [ ValueProcess::Level.new(value: dimension.base_level_decimal) ]
        components << ValueProcess::WhiteNoise.new(scale: dimension.noise_scale_decimal) if noise == :white
        components.concat(extra_components)

        new(
          family: family,
          seed: seed,
          dimensions: [ dimension ],
          processes: { dimension.semantic_key => ValueProcess.new(components) },
          effects: effects,
          confounders: confounders,
          notes: notes,
          **options
        )
      end
    end

    # Contamination indices are only known once the series has been
    # generated, so the confounder is enriched at read time rather than at
    # construction.
    def confounders
      super.map do |confounder|
        next confounder unless confounder.kind == :sparse_outliers

        injected = @processes.fetch(primary_semantic_key).component(:outliers)&.injected || []
        Confounder.new(
          kind: confounder.kind,
          semantic_keys: confounder.semantic_keys,
          details: confounder.details.merge(injected: injected)
        )
      end
    end
  end
end
