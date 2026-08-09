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

    def window_ending(finish, days)
      [ finish - days.days, finish ]
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
