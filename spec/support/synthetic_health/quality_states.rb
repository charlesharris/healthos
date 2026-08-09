# frozen_string_literal: true

module SyntheticHealth
  # The ten-state missingness taxonomy (SC §12, STAT-010).
  #
  # The harness never omits a measurement opportunity and never uses a
  # numeric stand-in for absence (STAT-002). Every opportunity in a generated
  # timeline produces exactly one Reading per dimension, and that Reading
  # carries one of these states. A gap is therefore always *visible* in the
  # data, and the reason for it is always recorded.
  #
  # This list is duplicated from Observation::QUALITY_STATES on purpose: the
  # harness must be loadable without Rails or a database (it is the acceptance
  # instrument for the statistical engine, and it travels to v2). The
  # duplication is guarded by `spec/synthetic_health/harness_spec.rb`, which
  # cross-checks against the model when Rails happens to be loaded.
  module QualityStates
    OBSERVED = "observed"
    NOT_EXPECTED = "not_expected"
    EXPECTED_BUT_MISSING = "expected_but_missing"
    SOURCE_UNAVAILABLE = "source_unavailable"
    DEVICE_NOT_REPORTING = "device_not_reporting"
    MANUAL_ENTRY_ABSENT = "manual_entry_absent"
    INVALID_MEASUREMENT = "invalid_measurement"
    EXCLUDED_BY_RULE = "excluded_by_rule"
    LATE_NOT_YET_ARRIVED = "late_not_yet_arrived"
    UNKNOWN = "unknown"

    ALL = [
      OBSERVED, NOT_EXPECTED, EXPECTED_BUT_MISSING, SOURCE_UNAVAILABLE,
      DEVICE_NOT_REPORTING, MANUAL_ENTRY_ABSENT, INVALID_MEASUREMENT,
      EXCLUDED_BY_RULE, LATE_NOT_YET_ARRIVED, UNKNOWN
    ].freeze

    # Every state other than `observed` denotes an absent measurement. None of
    # them carries a value — not even zero.
    MISSING = (ALL - [ OBSERVED ]).freeze

    # `not_expected` is not a gap at all (SC §12), so it is the only state
    # excluded from the completeness denominator (SC §13–14).
    IN_DENOMINATOR = (ALL - [ NOT_EXPECTED ]).freeze

    # Expected, and absent for a reason attributable to collection. These are
    # the shortfall states a measurement-behaviour Difference is built from
    # (SC §14, §18).
    EXPECTED_BUT_ABSENT = [
      EXPECTED_BUT_MISSING, SOURCE_UNAVAILABLE, DEVICE_NOT_REPORTING,
      MANUAL_ENTRY_ABSENT, LATE_NOT_YET_ARRIVED
    ].freeze

    def self.valid?(state)
      ALL.include?(state)
    end

    def self.validate!(state)
      return state if valid?(state)

      raise ArgumentError, "unknown quality_state #{state.inspect}; expected one of #{ALL.join(', ')}"
    end

    def self.observed?(state)
      state == OBSERVED
    end

    # Whether this state participates in the completeness denominator.
    def self.expected?(state)
      state != NOT_EXPECTED
    end
  end
end
