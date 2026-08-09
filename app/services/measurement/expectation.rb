# frozen_string_literal: true

module Measurement
  # Expected measurement opportunities (HO §27, SC §13).
  #
  # This is the object completeness rests on. SC §14 defines completeness as
  # usable expected opportunities over TOTAL expected opportunities, and
  # STAT-011 requires that denominator to be explicit — so something has to
  # say authoritatively how many readings *should* have existed. Counting only
  # what arrived can never answer that: a subject who stopped measuring
  # entirely would show 100% completeness of nothing.
  #
  # Output distinguishes three states, not two (HO §27):
  #
  #   expected      the protocol wanted a reading here
  #   not_expected  it did not — a lab not due today is not a gap (SC §13)
  #   unknown       we cannot say, because no expectation model is declared
  #
  # `unknown` is deliberately not folded into either. Treating it as
  # `not_expected` would silently inflate completeness; treating it as
  # `expected` would invent gaps that may not exist. Both are worse than
  # admitting we do not know, which is the posture the whole contract takes.
  class Expectation
    Opportunity = Struct.new(:date, :state, :expected_count, :reason, keyword_init: true) do
      def expected? = state == :expected
      def not_expected? = state == :not_expected
      def unknown? = state == :unknown
    end

    Window = Struct.new(:opportunities, :semantic_key, keyword_init: true) do
      # THE denominator (STAT-011). Only genuinely expected opportunities
      # count; `unknown` is excluded because including it would assert an
      # expectation we do not have.
      def expected_total = opportunities.select(&:expected?).sum(&:expected_count)

      def expected_days = opportunities.count(&:expected?)
      def not_expected_days = opportunities.count(&:not_expected?)
      def unknown_days = opportunities.count(&:unknown?)

      # True when no expectation model applies. A completeness ratio computed
      # over this is meaningless and must not be reported (SC §13: "unless
      # protocol says otherwise").
      def indeterminate? = expected_days.zero? && unknown_days.positive?
    end

    MODELS = {
      "daily_opportunity" => "Measurement::DailyOpportunity",
      "weekday_schedule" => "Measurement::WeekdaySchedule",
      "event_driven" => "Measurement::EventDriven"
    }.freeze

    def self.for_semantic(semantic_key)
      definition = Definitions::Registry.find(semantic_key)
      model_key = definition&.expected_measurement

      # No declared model means unknown, not "none expected". SC §13 requires
      # every completeness-sensitive dimension to declare an expectation
      # model; absence is a gap in configuration, and pretending otherwise
      # would fabricate a denominator.
      return Indeterminate.new if model_key.blank?

      name = MODELS[model_key.to_s]
      return Indeterminate.new if name.blank?

      name.constantize.new
    end

    def opportunities(subject:, window:, semantic_key:)
      raise NotImplementedError
    end

    protected

    # Days in the subject's own timezone. Completeness is day-based, and a UTC
    # day boundary would attribute an evening reading to the wrong day
    # (HO §121).
    #
    # HALF-OPEN — [start, finish) — matching every other window in the
    # codebase. One convention, stated once: a mixture is how a 21-day
    # baseline ends up measured as 22 days, and how two adjacent windows end
    # up both counting the same boundary reading.
    def local_dates(subject, window)
      zone = ActiveSupport::TimeZone[subject.timezone]
      from = window.first.in_time_zone(zone).to_date
      to = window.last.in_time_zone(zone).to_date
      (from...to).to_a.presence || [ from ]
    end
  end

  # Used when nothing is declared. Every day is `unknown`, so completeness is
  # indeterminate rather than a fabricated 100%.
  class Indeterminate < Expectation
    def opportunities(subject:, window:, semantic_key:)
      days = local_dates(subject, window).map do |date|
        Opportunity.new(date: date, state: :unknown, expected_count: 0,
                        reason: "no_expectation_model_declared")
      end

      Window.new(opportunities: days, semantic_key: semantic_key)
    end
  end

  # One expected reading per day. The reference model for daily vitals.
  class DailyOpportunity < Expectation
    def initialize(per_day: 1)
      @per_day = per_day
    end

    def opportunities(subject:, window:, semantic_key:)
      days = local_dates(subject, window).map do |date|
        Opportunity.new(date: date, state: :expected, expected_count: @per_day,
                        reason: "daily_protocol")
      end

      Window.new(opportunities: days, semantic_key: semantic_key)
    end
  end

  # SC §13's worked example: "BP protocol expects 5 measurement days/week."
  # Weekend days are not_expected — genuinely not a gap, so they must not
  # count against completeness.
  class WeekdaySchedule < Expectation
    def initialize(days: [ 1, 2, 3, 4, 5 ], per_day: 1)
      @days = days
      @per_day = per_day
    end

    def opportunities(subject:, window:, semantic_key:)
      days = local_dates(subject, window).map do |date|
        if @days.include?(date.wday)
          Opportunity.new(date: date, state: :expected, expected_count: @per_day,
                          reason: "scheduled_measurement_day")
        else
          Opportunity.new(date: date, state: :not_expected, expected_count: 0,
                          reason: "outside_measurement_schedule")
        end
      end

      Window.new(opportunities: days, semantic_key: semantic_key)
    end
  end

  # SC §13: "patient-reported symptom: event-driven, no daily completeness
  # denominator unless protocol says otherwise." Nothing is expected, so
  # completeness is not a meaningful question — distinct from indeterminate,
  # where we simply do not know.
  class EventDriven < Expectation
    def opportunities(subject:, window:, semantic_key:)
      days = local_dates(subject, window).map do |date|
        Opportunity.new(date: date, state: :not_expected, expected_count: 0,
                        reason: "event_driven_no_periodic_expectation")
      end

      Window.new(opportunities: days, semantic_key: semantic_key)
    end
  end
end
