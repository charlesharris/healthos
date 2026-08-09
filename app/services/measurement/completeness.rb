# frozen_string_literal: true

module Measurement
  # Completeness over a window (SC §14, STAT-011).
  #
  #   completeness = usable expected opportunities / total expected opportunities
  #
  # The denominator travels with the ratio, always. STAT-011 requires it and
  # SC §14 says "the UI should expose both the ratio and denominator" — 70%
  # of ten days and 70% of a hundred are not the same evidence, and a bare
  # ratio cannot tell them apart.
  #
  # Returns nil for the ratio when completeness is not a meaningful question,
  # rather than 0 or 1. A subject with no declared expectation model has
  # unknown completeness; an event-driven dimension has none. Both would be
  # misreported by any number at all.
  class Completeness
    # GOVERNED. Which quality states remove a day from the completeness
    # DENOMINATOR rather than counting against it.
    #
    # SC §14 defines completeness over "expected opportunities" but does not
    # say where invalid_measurement, excluded_by_rule and unknown sit. That
    # silence is a statistical decision, not an implementation detail: it
    # moves comparisons across STAT-012's 40/60/80 bands and therefore
    # decides whether a Difference can reach MODERATE or STRONG.
    #
    # Resolved 2026-08-09 (Charles):
    #
    #   invalid_measurement  COUNTS AGAINST completeness. The protocol wanted
    #                        a usable reading and did not get one. That the
    #                        attempt happened does not make the day measured.
    #   unknown              COUNTS AGAINST. We cannot show the opportunity
    #                        was met, and assuming it was would inflate
    #                        completeness on the strength of ignorance.
    #   excluded_by_rule     REMOVED FROM THE DENOMINATOR. We chose to discard
    #                        this reading. Penalising the subject's
    #                        completeness for our own exclusion double-counts
    #                        the exclusion — once by dropping the value, again
    #                        by making the day look missed.
    #
    # Changing this list changes every completeness ratio in the system.
    # It is one line on purpose (STAT-044).
    DENOMINATOR_EXEMPT_STATES = %w[excluded_by_rule].freeze

    Result = Struct.new(
      :ratio, :usable, :expected_total, :observed, :missing_by_state,
      :indeterminate, :reason, keyword_init: true
    ) do
      def indeterminate? = indeterminate

      # SC §14 wants both exposed together, so the pair is the primary
      # representation rather than the ratio with a footnote.
      def to_s
        return "indeterminate (#{reason})" if indeterminate?

        "#{(ratio * 100).round(1)}% (#{usable}/#{expected_total})"
      end

      # STAT-012's gates read this. Deliberately no `weak?`/`strong?` helpers
      # here — mapping completeness to an evidence ceiling is the gate's job
      # in 003-14, and putting it here would scatter a governed threshold.
      def percentage = indeterminate? ? nil : (ratio * 100)
    end

    def self.call(...) = new(...).call

    def initialize(subject:, semantic_key:, window:)
      @subject = subject
      @semantic_key = semantic_key
      @window = window
    end

    def call
      expectation = Expectation.for_semantic(@semantic_key)
      opportunities = expectation.opportunities(
        subject: @subject, window: @window, semantic_key: @semantic_key
      )

      observations = observations_in_window
      by_state = observations.group_by(&:quality_state).transform_values(&:size)

      if opportunities.expected_total.zero?
        return Result.new(
          ratio: nil, usable: 0, expected_total: 0,
          observed: by_state.fetch("observed", 0), missing_by_state: by_state,
          indeterminate: true,
          reason: opportunities.indeterminate? ? "no_expectation_model" : "nothing_expected_in_window"
        )
      end

      # "Usable" counts distinct expected days that produced an observed
      # reading, not observations. Three readings on one day are one day's
      # worth of completeness — counting them as three would let a single
      # enthusiastic day mask a week of silence (STAT-005).
      usable = usable_days(observations, opportunities)
      exempt = exempt_days(observations, opportunities)
      denominator = opportunities.expected_total - exempt

      if denominator <= 0
        return Result.new(
          ratio: nil, usable: usable, expected_total: 0,
          observed: by_state.fetch("observed", 0), missing_by_state: by_state,
          indeterminate: true, reason: "every_expected_day_excluded_by_rule"
        )
      end

      Result.new(
        ratio: Rational(usable, denominator).to_f,
        usable: usable,
        expected_total: denominator,
        observed: by_state.fetch("observed", 0),
        missing_by_state: by_state.except("observed"),
        indeterminate: false,
        reason: nil
      )
    end

    private

    def observations_in_window
      Observation
        .where(organization_id: @subject.organization_id, subject_id: @subject.id,
               semantic_key: @semantic_key)
        .where(observed_at: @window.first..@window.last)
        .to_a
    end

    # Days whose ONLY readings were excluded by rule. A day that also produced
    # a usable reading is not exempt — the exclusion of one reading does not
    # excuse the day.
    def exempt_days(observations, opportunities)
      expected_dates = opportunities.opportunities.select(&:expected?).map(&:date).to_set

      observations
        .group_by { |o| @subject.local_date(o.observed_at) }
        .count do |date, readings|
          expected_dates.include?(date) &&
            readings.all? { |r| DENOMINATOR_EXEMPT_STATES.include?(r.quality_state) }
        end
    end

    def usable_days(observations, opportunities)
      expected_dates = opportunities.opportunities.select(&:expected?).map(&:date).to_set

      observations
        .select(&:observed?)
        .map { |o| @subject.local_date(o.observed_at) }
        .uniq
        .count { |date| expected_dates.include?(date) }
    end
  end
end
