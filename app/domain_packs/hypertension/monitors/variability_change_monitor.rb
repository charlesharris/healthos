# frozen_string_literal: true

module Hypertension
  # Variability-change monitor v1 (epic 002-08).
  #
  # ⚠️ NON-CLINICAL. Every threshold here is an engineering fixture chosen to
  # make synthetic scenarios fire, NOT a clinical parameter. HO §175 requires
  # review and promotion before pilot, and prototype-scope.md keeps that gate
  # closed. Nothing in this file has been reviewed by a clinician.
  #
  # Scale is MAD, not standard deviation, and the algorithm is platform core's
  # (`Derivation::MeasurementBehavior::Variability`, SC §29) rather than a
  # second implementation here — one mis-cuffed 220 inflates an SD by an order
  # of magnitude and barely moves a MAD, and two versioned digests computing
  # the same statistic make reproducibility worse rather than better.
  #
  # What this monitor does and does not claim:
  #
  #   It observes that the spread of recent readings differs from the spread
  #   of earlier readings by more than a fixture amount, and says "a human may
  #   want to look."
  #
  #   It does NOT claim the subject's variability changed. A wider spread is
  #   produced just as readily by a new cuff, a different arm, a different
  #   time of day, or a household member measuring — which is why the source
  #   monitor watches the instrument in parallel and STAT-007 orders
  #   instrumentation before biology. Nor does it claim the two spreads are
  #   statistically distinguishable: that judgement needs completeness, source
  #   stability and an eligibility pipeline, and belongs to the evidence-gated
  #   comparison engine in epic 003. A Signal is a reason to look, never a
  #   finding.
  class VariabilityChangeMonitor < Monitoring::Monitor
    include MonitorWindows

    KEY = "blood_pressure_variability_change"
    VERSION = 1
    DOMAIN_KEY = "hypertension"

    SEMANTIC_KEY = "health.vital.blood_pressure.systolic"

    def self.key = KEY
    def self.version = VERSION
    def self.domain_key = DOMAIN_KEY

    # NON-CLINICAL FIXTURES (HO §175).
    def self.default_parameters
      {
        recent_days: 7,
        baseline_days: 14,
        # Denominator floors before the monitor will look at all. A
        # "worth looking at" filter, not a statistical sufficiency gate —
        # SC §15's completeness bands and SC §23's affected-window minimums
        # are the evidence gate's in 003-14, and restating them here would put
        # a governed value somewhere nobody reviews.
        minimum_recent_readings: 5,
        minimum_baseline_readings: 8,
        # mmHg of MAD movement. NON-CLINICAL.
        mad_shift_threshold_mmhg: 5,
        # Operational severity hint only, independent of evidence strength
        # (S2C-011).
        moderate_mad_shift_mmhg: 10
      }
    end

    def evaluate(subject:, as_of:)
      recent_window = day_aligned_window_ending(subject, as_of, parameters[:recent_days])
      baseline_window = day_aligned_window_ending(subject, recent_window.first, parameters[:baseline_days])

      recent = observed_readings(subject, SEMANTIC_KEY, recent_window)
      baseline = observed_readings(subject, SEMANTIC_KEY, baseline_window)

      if recent.size < parameters[:minimum_recent_readings] ||
         baseline.size < parameters[:minimum_baseline_readings]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "insufficient_points", recent: recent.size, baseline: baseline.size }
        )
      end

      recent_mad = mad_for(recent)
      baseline_mad = mad_for(baseline)

      if recent_mad.nil? || baseline_mad.nil?
        # The scale itself could not be estimated. Reported as insufficient
        # rather than as a shift of zero — an unmeasurable spread and an
        # unchanged spread are different statements (STAT-002's spirit).
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "insufficient_points", scale: "not_estimable" }
        )
      end

      shift = recent_mad - baseline_mad
      unless shift.abs >= parameters[:mad_shift_threshold_mmhg]
        return Result.not_triggered(
          window: recent_window, details: { reason: "below_threshold", shift: shift.to_f }
        )
      end

      triggered_result(subject, recent_window, recent, baseline, recent_mad, baseline_mad, shift)
    end

    private

    def mad_for(readings)
      outcome = Derivation::MeasurementBehavior::Variability.new(observations: readings).call
      outcome.computed? ? outcome.value_numeric : nil
    end

    def triggered_result(subject, window, recent, baseline, recent_mad, baseline_mad, shift)
      direction = shift.positive? ? "widening" : "narrowing"

      Result.new(
        triggered: true,
        signal_type: "variability_change",
        window: window,
        severity: shift.abs >= parameters[:moderate_mad_shift_mmhg] ? "moderate" : "low",
        attributes: {
          "direction" => direction,
          "scale" => "median_absolute_deviation",
          "recent_mad_mmhg" => recent_mad.to_s,
          "baseline_mad_mmhg" => baseline_mad.to_s,
          "mad_shift_mmhg" => shift.to_s,
          # Denominators travel with the observation (STAT-021); readings and
          # days are separate counts (STAT-004/005).
          "recent_reading_count" => recent.size,
          "baseline_reading_count" => baseline.size,
          "recent_day_count" => distinct_days(subject, recent),
          "baseline_day_count" => distinct_days(subject, baseline),
          "semantic_key" => SEMANTIC_KEY,
          # Explicit: this is descriptive, never causal (INV-34, STAT-001).
          "interpretation" => "descriptive_only"
        },
        # HO §34. Direction is part of the identity so a spread that widens
        # and later settles is two events rather than one repeated one.
        semantic_identity: "variability_change:#{direction}",
        details: { direction: direction, shift: shift.to_f }
      )
    end
  end
end
