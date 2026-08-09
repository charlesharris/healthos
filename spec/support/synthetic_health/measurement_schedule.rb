# frozen_string_literal: true

require "date"

require_relative "analysis_window"
require_relative "synthetic_subject"

module SyntheticHealth
  # A measurement opportunity: one slot on one subject-local day.
  #
  # Opportunities are the completeness denominator (SC §13–14). Every one of
  # them becomes a Reading — observed or explicitly missing — so the
  # denominator is recoverable from the generated data alone, with no
  # out-of-band knowledge of what "should" have been there.
  Opportunity = Struct.new(
    :index,
    :local_date,
    :slot,
    :expected,
    :observed_at,
    :phase,
    :day_index,
    keyword_init: true
  ) do
    def expected?
      expected
    end
  end

  # The protocol: which local times a subject is expected to measure at, and
  # on which weekdays.
  #
  # A day outside `expected_weekdays` still produces Readings — with
  # `not_expected` — because "no measurement was due" and "a measurement was
  # due and did not arrive" are different facts, and collapsing them is
  # exactly the error SC §12 exists to prevent.
  class MeasurementSchedule
    Slot = Struct.new(:name, :hour, :minute, keyword_init: true)

    # Morning and evening, matching a twice-daily home BP protocol. The
    # evening slot is late enough that, for a negative UTC offset, its UTC
    # timestamp lands on the following calendar day — so any engine that
    # groups by UTC date instead of subject-local date fails visibly.
    DEFAULT_SLOTS = [
      Slot.new(name: "morning", hour: 7, minute: 30),
      Slot.new(name: "evening", hour: 20, minute: 30)
    ].freeze

    ALL_WEEKDAYS = (0..6).to_a.freeze
    WEEKDAYS_ONLY = (1..5).to_a.freeze

    attr_reader :slots, :expected_weekdays

    def initialize(slots: DEFAULT_SLOTS, expected_weekdays: ALL_WEEKDAYS)
      raise ArgumentError, "at least one slot is required" if slots.empty?

      @slots = slots.freeze
      @expected_weekdays = Array(expected_weekdays).freeze
      freeze
    end

    def self.twice_daily(**options)
      new(**options)
    end

    def self.once_daily(**options)
      new(slots: [ DEFAULT_SLOTS.first ], **options)
    end

    # Five expected days a week — the SC §13 worked example. The weekend
    # opportunities are emitted as `not_expected`, which is what keeps the
    # completeness denominator honest.
    def self.weekday_protocol(**options)
      new(expected_weekdays: WEEKDAYS_ONLY, **options)
    end

    def expected_on?(date)
      @expected_weekdays.include?(date.wday)
    end

    def slots_per_day
      @slots.size
    end

    def opportunities(window:, subject:)
      index = -1

      window.dates.flat_map do |date|
        expected = expected_on?(date)
        phase = window.phase_for(date)
        day_index = window.day_index(date)

        @slots.map do |slot|
          index += 1
          Opportunity.new(
            index: index,
            local_date: date,
            slot: slot.name,
            expected: expected,
            observed_at: subject.utc_time_for(date, hour: slot.hour, minute: slot.minute),
            phase: phase,
            day_index: day_index
          )
        end
      end
    end

    def to_h
      {
        slots: @slots.map { |slot| { name: slot.name, hour: slot.hour, minute: slot.minute } },
        expected_weekdays: @expected_weekdays
      }
    end
  end
end
