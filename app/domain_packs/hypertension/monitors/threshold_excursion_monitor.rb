# frozen_string_literal: true

module Hypertension
  # Threshold-excursion monitor v1 (epic 002-07).
  #
  # ⚠️ NON-CLINICAL. Every threshold here is an engineering fixture chosen to
  # make synthetic scenarios fire, NOT a clinical parameter. HO §175 requires
  # review and promotion before pilot, and prototype-scope.md keeps that gate
  # closed. 150/90 mmHg look like clinical numbers and are not: nobody with a
  # medical qualification has seen this file.
  #
  # What this monitor does and does not claim:
  #
  #   It observes that some readings in a recent window fell outside a fixture
  #   band, and says "a human may want to look."
  #
  #   It does NOT claim the readings are accurate, that anything about the
  #   subject changed, or that the excursions are clinically significant. It
  #   has no baseline at all, so it cannot speak to change — that is the
  #   trajectory monitor's question and, properly gated, the comparison
  #   engine's in epic 003. It also does not treat its own count as evidence:
  #   six excursions from one afternoon and six across six days are the same
  #   number and very different observations, which is why both the reading
  #   count and the day count travel with the Signal (STAT-004/005/021).
  class ThresholdExcursionMonitor < Monitoring::Monitor
    include MonitorWindows

    KEY = "blood_pressure_threshold_excursion"
    VERSION = 1
    DOMAIN_KEY = "hypertension"

    SEMANTIC_KEY = "health.vital.blood_pressure.systolic"

    def self.key = KEY
    def self.version = VERSION
    def self.domain_key = DOMAIN_KEY

    # NON-CLINICAL FIXTURES (HO §175). Organization configuration overrides
    # them (HO §31); platform core ships none of its own.
    def self.default_parameters
      {
        window_days: 7,
        # mmHg band edges. NON-CLINICAL.
        high_mmhg: 150,
        low_mmhg: 90,
        # Denominator floor before the monitor will look at all. Deliberately
        # low: this is a "worth looking at" filter, not a statistical
        # sufficiency gate. The real gates are SC §11/§15/§23 in epic 003, and
        # duplicating them here would put a governed value somewhere nobody
        # reviews.
        minimum_readings: 3,
        minimum_excursions: 2,
        # Operational severity hint only, independent of evidence strength
        # (S2C-011). Severity says how loudly to knock, never how true it is.
        moderate_excursion_count: 4
      }
    end

    def evaluate(subject:, as_of:)
      window = day_aligned_window_ending(subject, as_of, parameters[:window_days])
      readings = observed_readings(subject, SEMANTIC_KEY, window)
        .select { |reading| reading.value_numeric.present? }

      if readings.size < parameters[:minimum_readings]
        return Result.not_triggered(
          window: window,
          details: { reason: "insufficient_points", readings: readings.size }
        )
      end

      above = readings.select { |reading| reading.value_numeric > parameters[:high_mmhg] }
      below = readings.select { |reading| reading.value_numeric < parameters[:low_mmhg] }

      # One Signal per evaluation. When both edges are crossed the busier one
      # is reported and both counts travel in the attributes, so the quieter
      # direction is recorded rather than hidden; a later window in which it
      # dominates raises its own Signal under a different semantic identity.
      direction, excursions = above.size >= below.size ? [ "above", above ] : [ "below", below ]

      if excursions.size < parameters[:minimum_excursions]
        return Result.not_triggered(
          window: window,
          details: { reason: "below_threshold", above: above.size, below: below.size }
        )
      end

      triggered_result(subject, window, readings, excursions, direction, above, below)
    end

    private

    def triggered_result(subject, window, readings, excursions, direction, above, below)
      Result.new(
        triggered: true,
        signal_type: "threshold_excursion",
        window: window,
        severity: excursions.size >= parameters[:moderate_excursion_count] ? "moderate" : "low",
        attributes: {
          "direction" => direction,
          "threshold_mmhg" => threshold_for(direction),
          "excursion_count" => excursions.size,
          "excursion_days" => distinct_days(subject, excursions),
          "excursion_count_above" => above.size,
          "excursion_count_below" => below.size,
          # Denominators travel with the observation (STAT-021), and readings
          # and days are reported separately (STAT-004/005) because a count of
          # readings is not a count of independent units.
          "reading_count" => readings.size,
          "reading_days" => distinct_days(subject, readings),
          "semantic_key" => SEMANTIC_KEY,
          # Explicit: this is descriptive, never causal (INV-34, STAT-001).
          "interpretation" => "descriptive_only"
        },
        # HO §34: the semantic event identity component of the dedup key.
        # Direction is included so a run of low readings is a genuinely
        # different event rather than a duplicate of an earlier high run.
        semantic_identity: "threshold_excursion:#{direction}",
        details: { direction: direction, excursions: excursions.size, readings: readings.size }
      )
    end

    def threshold_for(direction)
      direction == "above" ? parameters[:high_mmhg] : parameters[:low_mmhg]
    end
  end
end
