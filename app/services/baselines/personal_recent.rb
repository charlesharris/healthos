# frozen_string_literal: true

module Baselines
  # `personal_recent` v1 (epic 003-08, SC §20/§22, STAT-016/017).
  #
  # The subject compared against their own recent past. The simplest honest
  # baseline and, for a longitudinal platform, the default one: SC §20 rejects
  # a universal `normal`, and a population range would answer a different
  # question than "is this person different from how they have been".
  #
  # Domain-neutral by construction. The window length, the minimums and the
  # aggregation all come from the base class and governed configuration, so
  # this reads the same for post-op recovery or oncology as for hypertension.
  # A domain pack that knows a clinically meaningful cadence subclasses and
  # overrides the thresholds — SC §22 calls the generic ones "engineering
  # defaults only".
  class PersonalRecent < Definition
    KEY = "personal_recent"
    VERSION = 1

    def self.key = KEY
    def self.version = VERSION
    def self.baseline_type = "personal_recent"

    def build
      window = Telemetry::Windows.day_aligned_window_ending(
        subject, ends_at, self.class.eligible_lookback_days
      )

      readings = Telemetry::Windows.readings_in(subject, semantic_key, window)
      usable = readings.select { |r| r.observed? && r.value_numeric.present? }

      # SC §22's aggregation rule, applied BEFORE anything is summarised. A
      # day is one unit however many times it was measured (STAT-005).
      daily = usable
        .group_by { |r| subject.local_date(r.observed_at) }
        .transform_values { |day| median(day.map(&:value_numeric)) }
        .sort
        .to_h

      Result.new(
        definition: self.class,
        window: window,
        as_of: as_of,
        central_value: daily.empty? ? nil : median(daily.values),
        # A centre without a scale cannot support SC §29's robust
        # standardized effect, and a Comparison that recomputed one would be
        # reasoning about inputs the baseline never recorded.
        dispersion: daily.size >= 3 ? mad(daily.values) : nil,
        unit: usable.first&.unit,
        usable_units: daily.size,
        # STAT-004/021: readings and units are different numbers and both are
        # shown. `n=42` from 42 readings is on the forbidden list.
        raw_reading_count: readings.size,
        calendar_span_days: Telemetry::Windows.calendar_span_days(subject, usable),
        completeness: completeness_for(window),
        maturity: Analysis::BaselineMaturity.call(
          usable_units: daily.size,
          calendar_span_days: Telemetry::Windows.calendar_span_days(subject, usable)
        ),
        # STAT-002: what was missing, and in what way. Never imputed, never
        # dropped from the record — "we looked and it was not there" is
        # different evidence from "we did not look".
        missing_by_state: readings.reject(&:observed?).group_by(&:quality_state)
                                  .transform_values(&:size),
        source_summary: source_summary_for(usable),
        # INV-3: the exact rows, so a Finding built on this baseline drills
        # down to source records.
        inputs: usable,
        daily_values: daily
      )
    end

    private

    # The completeness ratio and its denominator, from the shared service
    # rather than recomputed here — one definition of completeness, so the
    # gates in 003-14 cannot be reading a different number from the one the
    # baseline reports.
    def completeness_for(window)
      Measurement::Completeness.call(
        subject: subject, semantic_key: semantic_key, window: window
      )
    end

    def source_summary_for(usable)
      profile = Measurement::SourceProfile.build(usable)

      {
        "method_mix" => profile.method_mix,
        "source_mix" => profile.source_mix
      }
    end

    def median(values)
      sorted = values.compact.sort
      return nil if sorted.empty?

      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    # Median absolute deviation. Robust to the outliers a home-measured series
    # is full of, where a standard deviation would be dominated by them.
    def mad(values)
      centre = median(values)
      return nil if centre.nil?

      median(values.map { |value| (value - centre).abs })
    end
  end
end
