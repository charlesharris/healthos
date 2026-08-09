# frozen_string_literal: true

require_relative "fixtures"
require_relative "scenario"
require_relative "trajectory_scenario"

module SyntheticHealth
  # The source-switch artifact family (HO §100–101, STAT-007/008/009).
  #
  # A subject's cuff is replaced partway through. The new cuff reads
  # consistently higher. Nothing whatsoever happens to the subject.
  #
  # The harness guarantees that structurally rather than rhetorically: the
  # calibration bias is applied AFTER the latent series is generated, so a
  # source-switch scenario and a null scenario built from the same seed have
  # byte-identical latent biology. A spec can therefore assert the strongest
  # possible form of the claim —
  #
  #   scenario.latent_series == null_equivalent.latent_series
  #
  # — and any difference the engine finds in the recorded values is, provably,
  # the instrument.
  #
  # The acceptance behaviour this exists to test (HO §101): the
  # instrumentation Finding outranks the biological one. Whether a given
  # switch fraction caps evidence at WEAK or suppresses biology entirely is
  # governed configuration (STAT-008/009); the harness only reports the mix it
  # produced, in `truth.realized[...][:phases][:affected][:source_mix]`.
  class SourceSwitchScenario < Scenario
    class << self
      # Every affected-window reading comes from the replacement instrument.
      def full_switch(seed:, offset: Fixtures::CUFF_OFFSET, **options)
        window = options.fetch(:window, AnalysisWindow.default)
        assemble(seed: seed, offset: offset, switch_date: window.affected_start, window: window,
                 **options.except(:window))
      end

      # The switch lands inside the affected window, leaving it genuinely
      # mixed. `fraction` is the proportion of affected DAYS recorded on the
      # replacement instrument; the realized fraction over readings is
      # reported in ground truth.
      def partial_switch(seed:, fraction: Fixtures::SOURCE_SWITCH_FRACTION, offset: Fixtures::CUFF_OFFSET, **options)
        window = options.fetch(:window, AnalysisWindow.default)
        assemble(seed: seed, offset: offset, switch_date: switch_date_for(window, fraction), window: window,
                 requested_fraction: fraction, **options.except(:window))
      end

      # Both at once: a real shift AND an instrument change. The hardest case,
      # and the one where conflating the two does the most damage.
      def with_biological_shift(seed:,
                                magnitude: Fixtures::LEVEL_SHIFT,
                                offset: Fixtures::CUFF_OFFSET,
                                fraction: Fixtures::SOURCE_SWITCH_FRACTION,
                                **options)
        window = options.fetch(:window, AnalysisWindow.default)
        dimension = options.fetch(:dimension, Dimensions::SYSTOLIC)
        magnitude = Decimal.cast(magnitude)

        assemble(
          seed: seed,
          offset: offset,
          switch_date: switch_date_for(window, fraction),
          window: window,
          requested_fraction: fraction,
          family: :source_switch_with_biology,
          extra_components: [ ValueProcess::LevelShift.new(magnitude: magnitude) ],
          effects: [
            Effect.new(
              kind: :level_shift,
              semantic_key: dimension.semantic_key,
              magnitude: magnitude,
              unit: dimension.unit,
              direction: magnitude.negative? ? :decrease : :increase,
              phase: :affected,
              cause: "injected sustained level shift, concurrent with an instrument change",
              details: {}
            )
          ],
          notes: [ "a real effect and an instrumentation artifact overlap; they must not be conflated (STAT-007)" ],
          **options.except(:window, :dimension)
        )
      end

      private

      # The first affected date recorded on the replacement instrument, such
      # that `fraction` of affected days fall on or after it.
      def switch_date_for(window, fraction)
        dates = window.affected_dates
        switched_days = (Decimal.cast(fraction) * dates.size).round.to_i.clamp(0, dates.size)
        return dates.last + 1 if switched_days.zero?

        dates[dates.size - switched_days]
      end

      def assemble(seed:,
                   offset:,
                   switch_date:,
                   window:,
                   dimension: Dimensions::SYSTOLIC,
                   family: :source_switch_artifact,
                   original_source: nil,
                   replacement_source: nil,
                   requested_fraction: nil,
                   extra_components: [],
                   effects: [],
                   notes: [],
                   **options)
        original = original_source || SyntheticSource.home_cuff
        replacement = replacement_source || SyntheticSource.replacement_cuff(calibration_offset: offset)

        components = [
          ValueProcess::Level.new(value: dimension.base_level_decimal),
          ValueProcess::WhiteNoise.new(scale: dimension.noise_scale_decimal)
        ].concat(extra_components)

        new(
          family: family,
          seed: seed,
          window: window,
          dimensions: [ dimension ],
          processes: { dimension.semantic_key => ValueProcess.new(components) },
          source_plan: SourcePlan.switch(from: original, to: replacement, at_date: switch_date),
          effects: effects,
          confounders: [
            Confounder.new(
              kind: :source_switch,
              semantic_keys: [ dimension.semantic_key ],
              details: {
                from_source: original.key,
                to_source: replacement.key,
                from_source_family: original.source_family,
                to_source_family: replacement.source_family,
                switch_date: switch_date.iso8601,
                calibration_offset: Decimal.cast(offset).to_s("F"),
                requested_affected_day_fraction: requested_fraction && Decimal.cast(requested_fraction).to_s("F"),
                note: "recorded values move; the latent series does not. Realized mix is in truth.realized."
              }.compact
            )
          ],
          notes: notes.empty? ? [ "no biological effect injected; the instrument changed, the subject did not" ] : notes,
          **options
        )
      end
    end

    # Convenience for the assertion this family exists to support: an
    # identically-seeded scenario with no instrument change and no injected
    # effect. Its latent series is byte-identical to this one's.
    def null_equivalent
      TrajectoryScenario.null(seed: seed, dimension: primary_dimension, window: window,
                              schedule: schedule, subject: subject)
    end
  end
end
