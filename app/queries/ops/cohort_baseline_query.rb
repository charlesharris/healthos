# frozen_string_literal: true

module Ops
  # Where a subject sits among the program's baselines (SC §64, §66; 002x-02).
  #
  # This is the question review asked for — "compare against other patients'
  # baselines" — and it is a different question from the one the cohort prior
  # answered before. Pooling every subject's raw readings and taking a share
  # lets a subject measuring four times a day outvote one measuring daily,
  # which SC §66 forbids:
  #
  #   "Default cohort analysis unit: subject, not individual observations.
  #    Subject-level features are computed first… This prevents patients with
  #    dense telemetry from dominating the sample."
  #
  # So the unit here is one materialized BaselineInstance per subject, and the
  # comparison is against the DISTRIBUTION of their centres.
  #
  # Descriptive only, and between-subject. Readings from different people are
  # not repeated measures of one person (STAT-021); a subject sitting high in
  # the program is a place to look, never a Finding, and SC §64 caps evidence
  # resting mainly on a cohort prior below STRONG.
  class CohortBaselineQuery < Tenanted::Query
    # SC §25's floor for provider-facing Difference RANKING. This surface
    # ranks nothing, so "descriptive aggregate display" applies below it — but
    # the reader has to be told which side of the line they are on rather than
    # assuming a strength the sample never had.
    RANKING_MINIMUM_SUBJECTS = 20

    Distribution = Struct.new(
      :subject_count, :median, :p25, :p75, :min, :max, :unit, :as_of,
      :maturity_counts, :subjects_with_data, :below_ranking_minimum,
      keyword_init: true
    ) do
      def any? = subject_count.positive?
      def below_ranking_minimum? = below_ranking_minimum

      # How many of the cohort's own baselines are strong enough to be worth
      # standing on. Shown because a distribution of immature baselines is a
      # distribution of noise, and nothing about the spread says so.
      def mature_or_partial = maturity_counts.values_at("mature", "partial").compact.sum

      def coverage = subjects_with_data.zero? ? nil : subject_count.to_f / subjects_with_data
    end

    Position = Struct.new(:value, :percentile, :inside_iqr, :unit, keyword_init: true)

    def initialize(organization:, semantic_key:, membership: nil, exclude_subject: nil)
      super(organization: organization, membership: membership)
      @semantic_key = semantic_key
      @exclude_subject = exclude_subject
    end

    def resolve = distribution

    def distribution
      @distribution ||= begin
        centres = baselines.filter_map { |row| row[:central_value]&.to_f }.sort

        Distribution.new(
          subject_count: centres.length,
          median: quantile(centres, 0.5), p25: quantile(centres, 0.25), p75: quantile(centres, 0.75),
          min: centres.first, max: centres.last,
          unit: baselines.filter_map { |row| row[:unit] }.first,
          as_of: baselines.filter_map { |row| row[:as_of] }.max,
          maturity_counts: baselines.group_by { |row| row[:maturity] }.transform_values(&:size),
          subjects_with_data: subjects_with_data_count,
          below_ranking_minimum: centres.length < RANKING_MINIMUM_SUBJECTS
        )
      end
    end

    # Where one value falls in that distribution. Reported as a percentile and
    # an inside/outside-the-middle-half flag rather than a z-score, because a
    # z-score implies a shape nobody has checked (SC §29 uses a ROBUST scale
    # for the same reason).
    def position_of(value)
      return nil if value.nil? || !distribution.any?

      centres = baselines.filter_map { |row| row[:central_value]&.to_f }.sort
      below = centres.count { |centre| centre < value }

      Position.new(
        value: value,
        percentile: ((below.to_f / centres.length) * 100).round,
        inside_iqr: distribution.p25 && value >= distribution.p25 && value <= distribution.p75,
        unit: distribution.unit
      )
    end

    private

    # One row per subject: their most recently materialized baseline for this
    # measure. A subject with several as_of snapshots contributes once, or the
    # cohort would silently weight whoever had been recomputed most often —
    # the same dense-telemetry bias SC §66 exists to prevent, arriving by a
    # different door.
    def baselines
      @baselines ||= begin
        scope = for_tenant(Analysis::BaselineInstance.all)
          .where(semantic_key: @semantic_key)
        scope = scope.where.not(subject_id: @exclude_subject.id) if @exclude_subject

        scope
          .order(:subject_id, as_of: :desc)
          .pluck(:subject_id, :central_value, :unit, :as_of, :maturity)
          .group_by(&:first)
          .map do |_subject_id, rows|
            latest = rows.first
            { central_value: latest[1], unit: latest[2], as_of: latest[3], maturity: latest[4] }
          end
      end
    end

    # The denominator for coverage: how many subjects COULD have a baseline.
    # Without it, "47 subjects" reads as the whole program when it might be
    # half of it — and a cohort that silently shrank makes every share
    # computed from it wrong by an unknown amount.
    def subjects_with_data_count
      @subjects_with_data_count ||= begin
        scope = for_tenant(Observation.all)
          .where(semantic_key: @semantic_key, quality_state: "observed")
        scope = scope.where.not(subject_id: @exclude_subject.id) if @exclude_subject

        scope.distinct.count(:subject_id)
      end
    end

    def quantile(sorted, fraction)
      return nil if sorted.empty?

      sorted[[ (sorted.length * fraction).floor, sorted.length - 1 ].min]
    end
  end
end
