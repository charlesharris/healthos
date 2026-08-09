# frozen_string_literal: true

module Telemetry
  # Day-aligned, half-open window arithmetic over a subject's own timeline.
  #
  # Platform core, not a domain pack. It was written for the hypertension
  # monitors, but nothing in it is disease-shaped — "aligned to the subject's
  # local midnight, half-open" is as true for post-op recovery or oncology as
  # it is for blood pressure, and the baseline machinery in epic 003 needs
  # exactly the same arithmetic. A second copy would eventually disagree with
  # the first about a boundary reading, and that disagreement would surface as
  # an unexplainable bias rather than as a failure.
  #
  # Windows are half-open — `[start, finish)` — so a recent window and the
  # baseline window that ends where it begins can never both count the same
  # reading. A double-counted boundary reading is a tiny, untraceable bias in
  # every before/after comparison built on top.
  module Windows
    module_function

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
    # (SC §13–14) and HO §121 makes timezone boundaries a required regression
    # case. A UTC boundary would put an evening reading on the wrong day and,
    # near a DST transition, silently change a window's length.
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
    # The day count travels next to the reading count so a reader can tell one
    # enthusiastic afternoon from a fortnight of measuring.
    def distinct_days(subject, readings)
      readings.map { |reading| subject.local_date(reading.observed_at) }.uniq.size
    end

    # Calendar days actually spanned by these readings, first to last
    # inclusive. Distinct from `distinct_days`: ten readings over a fortnight
    # span 14 days and occupy 10 of them, and SC §21 needs both because ten
    # readings crammed into three days is not a fortnight's baseline.
    def calendar_span_days(subject, readings)
      return 0 if readings.empty?

      dates = readings.map { |reading| subject.local_date(reading.observed_at) }
      (dates.max - dates.min).to_i + 1
    end
  end
end
