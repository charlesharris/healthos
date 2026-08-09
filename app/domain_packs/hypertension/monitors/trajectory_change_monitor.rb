# frozen_string_literal: true

module Hypertension
  # Trajectory-change monitor v1 (epic 001-10).
  #
  # ⚠️ NON-CLINICAL. Every threshold here is an engineering fixture chosen to
  # make synthetic scenarios fire, NOT a clinical parameter. HO §175 requires
  # review and promotion before pilot, and prototype-scope.md keeps that gate
  # closed. Nothing in this file has been reviewed by a clinician.
  #
  # What this monitor does and does not claim:
  #
  #   It observes that a recent window's median differs from a preceding
  #   window's median by more than a fixture amount, and says "a human may
  #   want to look."
  #
  #   It does NOT claim the difference is real, meaningful, or biological.
  #   That judgement belongs to the evidence-gated comparison engine in epic
  #   003, which weighs completeness, source stability and variance before
  #   saying anything. A Signal is a reason to look, never a finding.
  class TrajectoryChangeMonitor < Monitoring::Monitor
    KEY = "blood_pressure_trajectory_change"
    VERSION = 1
    DOMAIN_KEY = "hypertension"

    SUMMARY_KEY = "health.vital.blood_pressure.daily_summary"

    def self.key = KEY
    def self.version = VERSION
    def self.domain_key = DOMAIN_KEY

    # NON-CLINICAL FIXTURES (HO §175).
    def self.default_parameters
      {
        recent_days: 7,
        baseline_days: 14,
        # Minimum daily summaries on each side before the monitor will look at
        # all. Deliberately low: this is a "worth looking at" filter, not a
        # statistical sufficiency gate. The real gates are STAT-012/016/018 in
        # epic 003, and duplicating them here would put a threshold somewhere
        # nobody reviews.
        minimum_recent_points: 3,
        minimum_baseline_points: 5,
        # mmHg. NON-CLINICAL.
        shift_threshold_mmhg: 8
      }
    end

    def evaluate(subject:, as_of:)
      recent_window = window_ending(as_of, parameters[:recent_days])
      baseline_window = window_ending(recent_window.first, parameters[:baseline_days])

      recent = summaries_in(subject, recent_window)
      baseline = summaries_in(subject, baseline_window)

      if recent.size < parameters[:minimum_recent_points] ||
         baseline.size < parameters[:minimum_baseline_points]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "insufficient_points", recent: recent.size, baseline: baseline.size }
        )
      end

      recent_median = median(recent.map(&:value_numeric))
      baseline_median = median(baseline.map(&:value_numeric))
      shift = recent_median - baseline_median

      unless shift.abs >= parameters[:shift_threshold_mmhg]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "below_threshold", shift: shift.to_f }
        )
      end

      Result.new(
        triggered: true,
        signal_type: "blood_pressure_trajectory_change",
        window: recent_window,
        severity: shift.abs >= (parameters[:shift_threshold_mmhg] * 2) ? "moderate" : "low",
        attributes: {
          "recent_median" => recent_median.to_s,
          "baseline_median" => baseline_median.to_s,
          "shift_mmhg" => shift.to_s,
          "direction" => shift.positive? ? "increase" : "decrease",
          # Denominators travel with the observation (STAT-021), so a Case
          # built from this Signal can show what it was based on without
          # recomputing.
          "recent_point_count" => recent.size,
          "baseline_point_count" => baseline.size,
          # Explicit: this is descriptive, never causal (INV-34, STAT-001).
          "interpretation" => "descriptive_only"
        },
        # HO §34: the semantic event identity component of the dedup key.
        # Direction is included so a reversal is a genuinely different event
        # rather than a duplicate of the original.
        semantic_identity: "trajectory_shift:#{shift.positive? ? 'increase' : 'decrease'}",
        details: { shift: shift.to_f }
      )
    end

    private

    def window_ending(finish, days)
      [ finish - days.days, finish ]
    end

    def summaries_in(subject, window)
      DerivedSignal
        .computed
        .where(organization_id: subject.organization_id, subject_id: subject.id,
               semantic_key: SUMMARY_KEY)
        .where(window_ended_at: window.first...window.last)
        .order(:window_ended_at)
        .to_a
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end
  end
end
