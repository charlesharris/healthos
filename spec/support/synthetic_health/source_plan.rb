# frozen_string_literal: true

require_relative "synthetic_source"

module SyntheticHealth
  # Which source recorded which opportunity.
  #
  # Instrumentation is evaluated before biology (STAT-007) and a source change
  # can cap or suppress a biological reading of the same data
  # (STAT-008/009). To test that, the harness has to be able to change the
  # instrument without changing the subject — which is precisely what a
  # SourcePlan does: it selects a source per opportunity, and the source's
  # calibration bias is applied on top of an untouched latent series.
  class SourcePlan
    def self.constant(source)
      Constant.new(source)
    end

    # `at_date` is the first local date recorded on the replacement source.
    def self.switch(from:, to:, at_date:)
      Switch.new(from: from, to: to, at_date: at_date)
    end

    def self.per_phase(baseline:, affected:, gap: nil)
      PerPhase.new(baseline: baseline, affected: affected, gap: gap || baseline)
    end

    # Two sources interleaved throughout — a subject who uses whichever cuff
    # is at hand. A mixed window is a different instrumentation story from a
    # clean switch and should not be mistaken for one.
    def self.alternating(sources)
      Alternating.new(sources)
    end

    def source_for(opportunity)
      raise NotImplementedError
    end

    def sources
      raise NotImplementedError
    end

    def to_h
      raise NotImplementedError
    end

    class Constant < SourcePlan
      def initialize(source)
        @source = source
        freeze
      end

      def source_for(opportunity)
        @source
      end

      def sources
        [ @source ]
      end

      def to_h
        { plan: "constant", source: @source.key }
      end
    end

    class Switch < SourcePlan
      attr_reader :at_date

      def initialize(from:, to:, at_date:)
        @from = from
        @to = to
        @at_date = at_date
        freeze
      end

      def source_for(opportunity)
        opportunity.local_date >= @at_date ? @to : @from
      end

      def sources
        [ @from, @to ]
      end

      def to_h
        { plan: "switch", from: @from.key, to: @to.key, at_date: @at_date.iso8601 }
      end
    end

    class PerPhase < SourcePlan
      def initialize(baseline:, affected:, gap:)
        @by_phase = { baseline: baseline, affected: affected, gap: gap }.freeze
        freeze
      end

      def source_for(opportunity)
        @by_phase.fetch(opportunity.phase)
      end

      def sources
        @by_phase.values.uniq
      end

      def to_h
        { plan: "per_phase", sources: @by_phase.transform_values(&:key) }
      end
    end

    class Alternating < SourcePlan
      def initialize(sources)
        raise ArgumentError, "alternating requires at least two sources" if sources.size < 2

        @sources = sources.freeze
        freeze
      end

      def source_for(opportunity)
        @sources[opportunity.index % @sources.size]
      end

      def sources
        @sources
      end

      def to_h
        { plan: "alternating", sources: @sources.map(&:key) }
      end
    end
  end
end
