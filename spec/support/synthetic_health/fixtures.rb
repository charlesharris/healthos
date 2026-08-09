# frozen_string_literal: true

require_relative "decimal"

module SyntheticHealth
  # NON-CLINICAL fixture magnitudes (HO §175).
  #
  # Every number here is an engineering fixture chosen so a generated scenario
  # is unambiguous enough to be a useful acceptance test. NONE of them is a
  # clinical parameter, and none of them is a threshold, gate, or decision
  # rule.
  #
  # The distinction matters more than it looks. The harness's job is to
  # generate data whose ground truth is *known*, not to decide what counts as
  # a shift, what completeness is adequate, or when instrumentation
  # invalidates biology. Those live in versioned engine configuration under
  # statistical governance (STAT-044) and must never be inferred from — or
  # tuned to agree with — anything in this file.
  #
  # Consequently: specs assert against `scenario.truth`, which reports what
  # was actually generated, not against these constants. If a constant here
  # ever has to change to make an engine spec pass, the spec is asserting the
  # wrong thing.
  module Fixtures
    # --- trajectory magnitudes (mmHg-shaped, NON-CLINICAL) -----------------

    # Large enough that no reasonable method could miss it, so a scenario that
    # fails to surface it indicates an engine defect rather than a marginal
    # call.
    LEVEL_SHIFT = 12

    # Applied from the first affected day onward.
    TREND_SLOPE_PER_DAY = 0.6

    # AR(1) coefficient for the autocorrelation family. High on purpose: naive
    # per-reading statistics treat correlated samples as independent evidence
    # and will over-call. Robust aggregation to analytical units (SC §27)
    # should not.
    AR1_PHI = 0.85
    AR1_INNOVATION_SCALE = 3

    # Cyclic component for the phase-drift family. The period is deliberately
    # longer than the baseline window, so baseline and affected windows sample
    # different phases of the same unchanged process — a difference with no
    # sustained change behind it.
    SEASONAL_AMPLITUDE = 8
    SEASONAL_PERIOD_DAYS = 40

    # Sparse contamination: a handful of implausible readings among otherwise
    # ordinary ones (mis-cuffed arm, transcription slip).
    OUTLIER_COUNT = 3
    OUTLIER_MAGNITUDE = 40

    # --- instrumentation (NON-CLINICAL) ------------------------------------

    # Calibration bias between two cuffs. Purely instrumental: it moves the
    # recorded number without anything happening to the subject.
    CUFF_OFFSET = 9

    # Fraction of the affected window recorded on the replacement source in
    # the default source-switch family. Chosen as "most, but not all" so the
    # scenario has a genuinely mixed window; the harness expresses no opinion
    # about where a suppression boundary lies.
    SOURCE_SWITCH_FRACTION = 0.6

    # --- measurement behaviour (NON-CLINICAL) ------------------------------

    # Background dropout in an ordinary, well-adhering timeline.
    ROUTINE_MISSING_RATE = 0.05

    # Adherence collapse in the affected window of the missingness family.
    # Paired with ROUTINE_MISSING_RATE this is a large change in measurement
    # behaviour with NO change in the underlying biology — the harness
    # guarantees the latter by construction, not by assertion.
    COLLAPSED_MISSING_RATE = 0.6

    # --- dimension shape (NON-CLINICAL) ------------------------------------

    SYSTOLIC_BASE = 128
    SYSTOLIC_NOISE = 6
    DIASTOLIC_BASE = 78
    DIASTOLIC_NOISE = 4
    PULSE_BASE = 68
    PULSE_NOISE = 5

    # How much of a systolic movement shows up in diastolic when both come
    # from the same cuff records. Not a physiological constant — it exists so
    # correlated-family scenarios produce genuinely redundant dimensions
    # (SC §49–50, STAT-033).
    DIASTOLIC_COUPLING = 0.6

    def self.decimal(name)
      Decimal.cast(const_get(name))
    end
  end
end
