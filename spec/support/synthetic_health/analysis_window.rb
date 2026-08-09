# frozen_string_literal: true

require "date"

module SyntheticHealth
  # The baseline / gap / affected day structure a scenario is generated over.
  #
  # Defaults are sized against the generic v0.1 baseline and affected-window
  # minimums (SC §22–23: 10 usable baseline days minimum, 21 target, 14-day
  # minimum span; 5 usable affected days, 7-day minimum span) so an ordinary
  # scenario clears them comfortably and a deliberately starved one can be
  # built by shrinking the window. Note what this is NOT: the harness does not
  # decide whether a window is adequate. It generates a window of a stated
  # size and reports what it generated.
  class AnalysisWindow
    DEFAULT_BASELINE_DAYS = 28
    DEFAULT_AFFECTED_DAYS = 14

    # Fixed anchor so scenarios do not drift with the wall clock. A Monday, so
    # weekday-limited protocols line up with window boundaries.
    DEFAULT_START = Date.new(2026, 1, 5)

    PHASES = %i[baseline gap affected].freeze

    attr_reader :baseline_start, :baseline_days, :gap_days, :affected_days

    def initialize(baseline_start: DEFAULT_START,
                   baseline_days: DEFAULT_BASELINE_DAYS,
                   gap_days: 0,
                   affected_days: DEFAULT_AFFECTED_DAYS)
      raise ArgumentError, "baseline_days must be positive" unless baseline_days.positive?
      raise ArgumentError, "affected_days must be positive" unless affected_days.positive?
      raise ArgumentError, "gap_days must not be negative" if gap_days.negative?

      @baseline_start = baseline_start
      @baseline_days = baseline_days
      @gap_days = gap_days
      @affected_days = affected_days
      freeze
    end

    def self.default(**options)
      new(**options)
    end

    # A window too short to support a longitudinal comparison. Exists so
    # "Case may exist, Comparison returns insufficient evidence" (HO §101) is
    # generatable rather than hand-rolled.
    def self.sparse(baseline_days: 6, affected_days: 3, **options)
      new(baseline_days: baseline_days, affected_days: affected_days, **options)
    end

    def baseline_end
      @baseline_start + (@baseline_days - 1)
    end

    def gap_start
      baseline_end + 1
    end

    def gap_end
      baseline_end + @gap_days
    end

    def affected_start
      gap_end + 1
    end

    def affected_end
      affected_start + (@affected_days - 1)
    end

    def start_date
      @baseline_start
    end

    def end_date
      affected_end
    end

    def baseline_dates
      (@baseline_start..baseline_end).to_a
    end

    def gap_dates
      return [] if @gap_days.zero?

      (gap_start..gap_end).to_a
    end

    def affected_dates
      (affected_start..affected_end).to_a
    end

    def dates
      (start_date..end_date).to_a
    end

    def total_days
      @baseline_days + @gap_days + @affected_days
    end

    def phase_for(date)
      return :baseline if date <= baseline_end
      return :affected if date >= affected_start

      :gap
    end

    def dates_for(phase)
      case phase
      when :baseline then baseline_dates
      when :gap then gap_dates
      when :affected then affected_dates
      else raise ArgumentError, "unknown phase #{phase.inspect}"
      end
    end

    def day_index(date)
      (date - start_date).to_i
    end

    def to_h
      {
        baseline_start: @baseline_start.iso8601,
        baseline_end: baseline_end.iso8601,
        baseline_days: @baseline_days,
        gap_days: @gap_days,
        affected_start: affected_start.iso8601,
        affected_end: affected_end.iso8601,
        affected_days: @affected_days
      }
    end
  end
end
