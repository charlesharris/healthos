# frozen_string_literal: true

module Hypertension
  # Window arithmetic shared by the hypertension monitor pack.
  #
  # Windows are half-open — `[start, finish)` — so a recent window and the
  # baseline window that ends where it begins can never both count the same
  # reading. Double-counting a boundary reading would show up as a tiny,
  # untraceable bias in every before/after comparison the pack makes.
  module MonitorWindows
    private

    # Day-aligned in the SUBJECT'S timezone, half-open: `[start, finish)`.
    #
    # Aligning to local midnight rather than to the evaluation instant means a
    # window's span in days equals the number of calendar dates it covers, so
    # `Derivation::MeasurementBehavior::Frequency` — whose denominator is the
    # calendar-date count — is the correct algorithm rather than an
    # approximation of one. Before alignment a 7x24h window ending mid-day
    # touched 8 dates and a 21-day baseline touched 22, scaling the two sides
    # of a ratio by different factors.
    #
    # Local midnight, not UTC: completeness and cadence are day-based
    # (SC §13-14) and HO §121 makes timezone boundaries a required regression
    # case. A UTC boundary would put an evening reading on the wrong day and,
    # near a DST transition, silently change a window's length.
    #
    # Half-open so a recent window and the baseline that ends where it begins
    # can never both count the same reading — a double-counted boundary
    # reading is a tiny, untraceable bias in every before/after comparison the
    # pack makes.
    def day_aligned_window_ending(subject, finish, days)
      zone = ActiveSupport::TimeZone[subject.timezone]
      finish_boundary = finish.in_time_zone(zone).beginning_of_day
      [ finish_boundary - days.days, finish_boundary ]
    end

    # Every row in the window, missing markers included. HO §28's taxonomy
    # rows are real evidence about measurement behaviour, so callers that need
    # a raw denominator get one (STAT-011/021).
    def readings_in(subject, semantic_key, window)
      Observation
        .where(organization_id: subject.organization_id, subject_id: subject.id,
               semantic_key: semantic_key)
        .where(observed_at: window.first...window.last)
        .order(:observed_at)
        .to_a
    end

    def observed_readings(subject, semantic_key, window)
      readings_in(subject, semantic_key, window).select(&:observed?)
    end

    # STAT-004/005: forty-two readings are not forty-two independent units.
    # Monitors report the day count next to the reading count so a reader can
    # tell one enthusiastic afternoon from a fortnight of measuring.
    def distinct_days(subject, readings)
      readings.map { |reading| subject.local_date(reading.observed_at) }.uniq.size
    end
  end
end
