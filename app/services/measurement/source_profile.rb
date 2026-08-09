# frozen_string_literal: true

module Measurement
  # What was recording, and did it change (HO §20, §29; STAT-003, STAT-007).
  #
  # This is the object STAT-007's ordering rests on: "source/method changes
  # evaluated BEFORE biology." If the cuff was swapped for a manual reading
  # halfway through the affected window, the apparent shift may be an artifact
  # of the instrument rather than anything about the subject — and SC §11
  # caps biological evidence at WEAK past 30% source change and suppresses it
  # past 50%.
  #
  # Reports the source MIX, not a boolean. "The source changed" is far less
  # useful than "62% of the affected window came from a different device than
  # the baseline", because the thresholds in SC §11 are proportions.
  class SourceProfile
    Result = Struct.new(
      :source_mix, :method_mix, :device_ids, :dominant_source_id,
      :total, :indeterminate, keyword_init: true
    ) do
      def indeterminate? = indeterminate

      # Share of readings NOT from the dominant source. SC §11's threshold
      # input.
      def minority_share
        return nil if indeterminate? || total.zero?

        dominant = source_mix.values.max || 0
        Rational(total - dominant, total).to_f
      end

      def single_source? = !indeterminate? && source_mix.size == 1
    end

    # How much of `affected` came from somewhere `baseline` did not.
    #
    # Deliberately returns the proportion and nothing else. Mapping it to
    # WEAK or suppressed is SC §11's job in the evidence gate (003-15) —
    # putting the 30% and 50% thresholds here would bury governed values in a
    # derivation, the same trap avoided in 001-09 and 001-10.
    Comparison = Struct.new(:changed_share, :affected, :baseline, :indeterminate, keyword_init: true) do
      def indeterminate? = indeterminate
    end

    def self.for_window(subject:, semantic_key:, window:)
      observations = Observation
        .where(organization_id: subject.organization_id, subject_id: subject.id,
               semantic_key: semantic_key)
        .where(observed_at: window.first..window.last)
        .where(quality_state: "observed")
        .to_a

      build(observations)
    end

    def self.build(observations)
      return Result.new(source_mix: {}, method_mix: {}, device_ids: [], total: 0,
                        indeterminate: true) if observations.empty?

      source_mix = observations.group_by(&:source_id).transform_values(&:size)
      method_mix = observations.group_by(&:recording_method).transform_values(&:size)

      Result.new(
        source_mix: source_mix,
        method_mix: method_mix,
        device_ids: observations.filter_map(&:device_id).uniq,
        dominant_source_id: source_mix.max_by { |_, count| count }&.first,
        total: observations.size,
        indeterminate: false
      )
    end

    # SC §11's input: the proportion of the affected window recorded by a
    # source that did not dominate the baseline.
    def self.compare(affected:, baseline:)
      if affected.indeterminate? || baseline.indeterminate?
        # Cannot say the source changed, and cannot say it did not. Reported
        # as indeterminate rather than 0 — a false "no change" would let a
        # biological reading through unqualified (STAT-007).
        return Comparison.new(changed_share: nil, affected: affected, baseline: baseline,
                              indeterminate: true)
      end

      baseline_sources = baseline.source_mix.keys.to_set
      changed = affected.source_mix.reject { |source_id, _| baseline_sources.include?(source_id) }
        .values.sum

      Comparison.new(
        changed_share: Rational(changed, affected.total).to_f,
        affected: affected, baseline: baseline, indeterminate: false
      )
    end
  end
end
