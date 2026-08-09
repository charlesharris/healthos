# frozen_string_literal: true

module Hypertension
  # Measurement-frequency-change monitor v1 (epic 002-09).
  #
  # ⚠️ NON-CLINICAL. Every threshold here is an engineering fixture chosen to
  # make synthetic scenarios fire, NOT a clinical parameter. HO §175 requires
  # review and promotion before pilot, and prototype-scope.md keeps that gate
  # closed. Nothing in this file has been reviewed by a clinician.
  #
  # HO §29 and STAT-003: measurement behaviour is first-class evidence, not a
  # data-quality annotation. A subject who stopped measuring and a subject who
  # is measuring fine are indistinguishable in the values alone, and this is
  # the dimension that separates them. The monitor lives in the domain pack
  # because the stream it watches and the fixture ratios are disease-shaped;
  # the underlying idea is domain-neutral and would read identically for
  # post-op recovery or oncology (INV-35).
  #
  # What this monitor does and does not claim:
  #
  #   It observes that recent measurements arrived at a materially lower rate
  #   than earlier ones, and says "a human may want to look."
  #
  #   It does NOT claim the subject is unwell, disengaged, or non-adherent —
  #   a broken cuff, a holiday, a hospital admission and a dead phone battery
  #   all look like this. Temporal association is not causation. It does not
  #   claim the gap invalidates anything either: capping or suppressing
  #   biological evidence on the strength of missing data is SC §15/§16's
  #   judgement, made by the evidence gate in 003-14, and a cadence Signal
  #   deliberately stops short of it.
  #
  # Only a DROP fires. A cadence increase is real and analyzable behaviour,
  # but the operational work this Signal correlates into is HO §42's
  # `monitoring_interruption` — "Monitoring interrupted" — and a subject who
  # started measuring more is not that piece of work. The increase stays
  # available to the comparison engine as measurement-behaviour data.
  class MeasurementFrequencyChangeMonitor < Monitoring::Monitor
    include MonitorWindows

    KEY = "measurement_frequency_change"
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
        baseline_days: 21,
        # Denominator floor before the monitor will look at all. There is no
        # cadence to have dropped if there was never a cadence.
        minimum_baseline_readings: 7,
        # Fires when the recent rate has fallen to two thirds or less of the
        # baseline rate. NON-CLINICAL, and deliberately not one of SC §15's
        # or SC §16's numbers: a monitor decides whether something is worth a
        # human looking at, never whether it counts as evidence.
        cadence_retained_ratio: 0.66,
        # Operational severity hint only, independent of evidence strength
        # (S2C-011).
        steep_cadence_retained_ratio: 0.2
      }
    end

    def evaluate(subject:, as_of:)
      recent_window = window_ending(as_of, parameters[:recent_days])
      baseline_window = window_ending(recent_window.first, parameters[:baseline_days])

      recent = observed_readings(subject, SEMANTIC_KEY, recent_window)
      baseline = observed_readings(subject, SEMANTIC_KEY, baseline_window)

      if baseline.size < parameters[:minimum_baseline_readings]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "insufficient_points", recent: recent.size, baseline: baseline.size }
        )
      end

      # Zero recent readings is a recorded fact about measurement behaviour,
      # not a zero-imputed value — STAT-002 forbids inventing a biological
      # zero from absence, and says nothing against counting how often a
      # measurement actually happened.
      recent_rate = rate_per_day(recent.size, parameters[:recent_days])
      baseline_rate = rate_per_day(baseline.size, parameters[:baseline_days])
      retained = (recent_rate / baseline_rate).round(4)

      if retained > parameters[:cadence_retained_ratio]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "below_threshold", retained_ratio: retained.to_f }
        )
      end

      triggered_result(subject, recent_window, recent, baseline, recent_rate, baseline_rate, retained)
    end

    private

    # Deliberately the window's exact span rather than the count of calendar
    # dates it touches. `Derivation::MeasurementBehavior::Frequency` reports
    # the same quantity over day-aligned windows, where the calendar count is
    # the right denominator; over a rolling window ending mid-day it is not,
    # and a recent and a baseline window would be scaled by different factors.
    def rate_per_day(count, days)
      (BigDecimal(count) / days).round(4)
    end

    def triggered_result(subject, window, recent, baseline, recent_rate, baseline_rate, retained)
      Result.new(
        triggered: true,
        signal_type: "measurement_frequency_change",
        window: window,
        severity: retained <= parameters[:steep_cadence_retained_ratio] ? "moderate" : "low",
        attributes: {
          "direction" => "decrease",
          "recent_rate_per_day" => recent_rate.to_s,
          "baseline_rate_per_day" => baseline_rate.to_s,
          "retained_ratio" => retained.to_s,
          # Denominators travel with the observation (STAT-021). The day
          # spans are the denominators the rates were computed over, and the
          # day counts are the units actually measured on (STAT-004/005).
          "recent_reading_count" => recent.size,
          "baseline_reading_count" => baseline.size,
          "recent_day_count" => distinct_days(subject, recent),
          "baseline_day_count" => distinct_days(subject, baseline),
          "recent_window_days" => parameters[:recent_days],
          "baseline_window_days" => parameters[:baseline_days],
          "semantic_key" => SEMANTIC_KEY,
          # Explicit: this is descriptive, never causal (INV-34, STAT-001).
          "interpretation" => "descriptive_only"
        },
        # HO §34. Direction is part of the identity even though only one
        # direction currently fires, so that adding the other later cannot
        # silently collapse two different events onto one dedup key.
        semantic_identity: "measurement_frequency_change:decrease",
        details: { direction: "decrease", retained_ratio: retained.to_f }
      )
    end
  end
end
