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

      Result.new(
        ratio: Rational(usable, opportunities.expected_total).to_f,
        usable: usable,
        expected_total: opportunities.expected_total,
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
