# frozen_string_literal: true

module Derivation
  # Measurement-behaviour derived signals (HO §29, STAT-003).
  #
  # HO §29 is emphatic: "these are first-class evidence. They are not merely
  # data-quality annotations." That distinction is the product. A patient
  # whose readings got worse and a patient who started measuring differently
  # look identical in the values alone — these dimensions are what separates
  # them, and STAT-035 lets a measurement Finding outrank a biological one
  # precisely because of it.
  #
  # Platform core, not domain pack (INV-35): measurement behaviour is
  # observable for post-op recovery and oncology exactly as it is for
  # hypertension.
  module MeasurementBehavior
    # How often readings were actually recorded, per day of the window.
    #
    # Distinct from completeness: frequency asks "how much did they measure",
    # completeness asks "how much of what was expected". A subject with no
    # expectation model has no completeness but still has a frequency, and a
    # subject measuring three times daily against a once-daily protocol has
    # 100% completeness and a frequency of 3.
    class Frequency < Algorithm
      KEY = "measurement_frequency"
      VERSION = 1

      def self.key = KEY
      def self.version = VERSION
      def self.parameters = { unit: "measurements_per_day" }

      def initialize(observations:, window:, subject:)
        @observations = observations
        @window = window
        @subject = subject
      end

      def call
        raw = @observations.to_a
        observed = raw.select(&:observed?)
        days = window_days

        return insufficient(raw) if days.zero?

        Outcome.new(
          value_numeric: (BigDecimal(observed.size) / days).round(4),
          unit: "measurements_per_day",
          inputs: observed,
          usable_input_count: observed.size,
          raw_input_count: raw.size,
          status: "computed"
        )
      end

      private

      def insufficient(raw)
        Outcome.new(value_numeric: nil, unit: nil, inputs: [],
                    usable_input_count: 0, raw_input_count: raw.size,
                    status: "insufficient_input")
      end

      # Windows are HALF-OPEN — [start, finish) — throughout the codebase, so
      # the day count is the plain difference between the boundary dates with
      # no +1. An inclusive count here silently measured a 21-day baseline as
      # 22 days, scaling the two sides of a before/after ratio by different
      # factors. Found when the monitor pack started reusing this algorithm
      # instead of carrying its own copy.
      def window_days
        zone = ActiveSupport::TimeZone[@subject.timezone]
        days = (@window.last.in_time_zone(zone).to_date - @window.first.in_time_zone(zone).to_date).to_i
        days.positive? ? days : 1
      end
    end

    # Days since the most recent observed reading.
    #
    # A leading indicator that completeness cannot give: completeness over a
    # 14-day window looks similar whether the gap is spread out or is a solid
    # week of silence ending yesterday. This distinguishes them.
    class DaysSinceLast < Algorithm
      KEY = "measurement_days_since_last"
      VERSION = 1

      def self.key = KEY
      def self.version = VERSION

      def initialize(observations:, as_of:, subject:)
        @observations = observations
        @as_of = as_of
        @subject = subject
      end

      def call
        latest = @observations.select(&:observed?).max_by(&:observed_at)

        if latest.nil?
          # No reading at all in the window. Deliberately NOT reported as a
          # large number — "infinity days since last" is a different claim
          # from "we have no reading in this window", and a numeric stand-in
          # would be zero-imputation's cousin (STAT-002).
          return Outcome.new(value_numeric: nil, unit: nil, inputs: [],
                             usable_input_count: 0, raw_input_count: @observations.size,
                             status: "insufficient_input")
        end

        days = (@subject.local_date(@as_of) - @subject.local_date(latest.observed_at)).to_i

        Outcome.new(
          value_numeric: BigDecimal(days), unit: "days", inputs: [ latest ],
          usable_input_count: 1, raw_input_count: @observations.size, status: "computed"
        )
      end
    end

    # Share of readings entered by a person rather than captured by a device.
    #
    # STAT-003 and SC §16 both care: a manually entered value is subject to
    # recall, rounding and selection in ways a device reading is not, and SC
    # §16 caps biological evidence at WEAK for behaviour-dependent signals
    # when missingness shifts.
    class ManualEntryFrequency < Algorithm
      KEY = "measurement_manual_entry_frequency"
      VERSION = 1

      MANUAL_METHODS = %w[manual_entry device_manual_transcription clinician_entered].freeze

      def self.key = KEY
      def self.version = VERSION
      def self.parameters = { manual_methods: MANUAL_METHODS }

      def initialize(observations:)
        @observations = observations
      end

      def call
        observed = @observations.select(&:observed?)
        return insufficient if observed.empty?

        manual = observed.count { |o| MANUAL_METHODS.include?(o.recording_method) }

        Outcome.new(
          value_numeric: (BigDecimal(manual) / observed.size).round(4),
          unit: "ratio", inputs: observed,
          usable_input_count: observed.size, raw_input_count: @observations.size,
          status: "computed"
        )
      end

      private

      def insufficient
        Outcome.new(value_numeric: nil, unit: nil, inputs: [],
                    usable_input_count: 0, raw_input_count: @observations.size,
                    status: "insufficient_input")
      end
    end

    # Dispersion of readings within the window (SC §29's robust scale).
    #
    # MAD rather than standard deviation: SC §29 prefers a robust scale, and
    # one mis-cuffed 220 inflates an SD far more than it does a MAD. SC §29
    # also says to omit a standardized value when the scale is zero or poorly
    # estimated, which is why a degenerate MAD produces
    # `insufficient_input` rather than 0.
    class Variability < Algorithm
      KEY = "measurement_variability"
      VERSION = 1
      MINIMUM_READINGS = 3

      def self.key = KEY
      def self.version = VERSION
      def self.parameters = { scale: "median_absolute_deviation", minimum_readings: MINIMUM_READINGS }

      def initialize(observations:)
        @observations = observations
      end

      def call
        values = @observations.select(&:observed?).filter_map(&:value_numeric)
        return insufficient if values.size < MINIMUM_READINGS

        med = median(values)
        mad = median(values.map { |v| (v - med).abs })

        Outcome.new(
          value_numeric: mad, unit: @observations.first&.unit,
          inputs: @observations.select(&:observed?),
          usable_input_count: values.size, raw_input_count: @observations.size,
          status: "computed"
        )
      end

      private

      def insufficient
        Outcome.new(value_numeric: nil, unit: nil, inputs: [],
                    usable_input_count: 0, raw_input_count: @observations.size,
                    status: "insufficient_input")
      end

      def median(values)
        sorted = values.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
      end
    end
  end
end
