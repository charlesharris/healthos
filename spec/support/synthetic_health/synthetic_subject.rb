# frozen_string_literal: true

require "date"

require_relative "randomness"

module SyntheticHealth
  # A subject — never "patient" — as plain data.
  #
  # Carries only what the statistics depend on: a stable key, a UTC offset (so
  # analytical days can be built in *subject-local* time, HO §121), and
  # opaque attributes a domain pack may want for cohort scenarios.
  #
  # The offset is a fixed integer rather than a live tz database lookup
  # because the harness must run without ActiveSupport. That means DST
  # transitions are not modelled; scenarios that need one set the offset
  # explicitly and document it. The timezone name is carried alongside so a
  # spec persisting these can populate Subject#timezone honestly.
  class SyntheticSubject
    # Negative-offset defaults are chosen on purpose: with a 20:30 local
    # evening slot, an America/New_York subject records at 01:30 UTC the
    # *following* calendar day. Any code that groups by UTC date instead of
    # subject-local date is wrong, and this default makes it wrong loudly.
    DEFAULT_TIMEZONE = "America/New_York"
    DEFAULT_UTC_OFFSET_MINUTES = -300

    COHORT_TIMEZONES = [
      [ "America/New_York", -300 ],
      [ "America/Chicago", -360 ],
      [ "America/Denver", -420 ],
      [ "America/Los_Angeles", -480 ],
      [ "UTC", 0 ],
      [ "Europe/London", 0 ],
      [ "Europe/Berlin", 60 ],
      [ "Asia/Tokyo", 540 ]
    ].freeze

    attr_reader :key, :timezone, :utc_offset_minutes, :attributes

    def initialize(key:, timezone: DEFAULT_TIMEZONE, utc_offset_minutes: DEFAULT_UTC_OFFSET_MINUTES, attributes: {})
      @key = key
      @timezone = timezone
      @utc_offset_minutes = Integer(utc_offset_minutes)
      @attributes = attributes.freeze
      freeze
    end

    def self.default(key: "subj_0001", **options)
      new(key: key, **options)
    end

    # Deterministic cohort. Timezones vary by position, not by RNG, so a
    # cohort of 100 is stable and inspectable; the seed only exists so callers
    # can vary opaque attributes if they need to.
    def self.cohort(size:, seed:, prefix: "subj")
      streams = SeedStreams.new(seed)
      rng = streams.for("cohort")

      Array.new(size) do |index|
        timezone, offset = COHORT_TIMEZONES[index % COHORT_TIMEZONES.size]
        new(
          key: format("%s_%04d", prefix, index + 1),
          timezone: timezone,
          utc_offset_minutes: offset,
          attributes: { cohort_index: index, enrollment_offset_days: rng.rand(0..27) }
        )
      end
    end

    # The analytical day a UTC instant belongs to for THIS subject
    # (SC §13–14: day-based completeness denominators are subject-local).
    def local_date(time)
      (time.utc + (@utc_offset_minutes * 60)).to_date
    end

    # UTC instant for a local wall-clock time on a local date.
    def utc_time_for(date, hour:, minute:)
      Time.utc(date.year, date.month, date.day, hour, minute) - (@utc_offset_minutes * 60)
    end

    def to_h
      { key: @key, timezone: @timezone, utc_offset_minutes: @utc_offset_minutes, attributes: @attributes }
    end
  end
end
