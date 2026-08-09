# frozen_string_literal: true

module Hypertension
  # Daily BP summary v1 (epic 001-09; HO §24 domain pack derived_signals).
  #
  # Median, not mean. SC §29 prefers robust continuous summaries, and a single
  # mis-cuffed reading of 220 would drag a mean far enough to look like a
  # genuine shift. The registry declares `aggregation: median` for these keys,
  # so the algorithm and the semantic definition agree.
  #
  # NON-CLINICAL: MINIMUM_READINGS is an engineering fixture, not a clinical
  # parameter (HO §175). It is in `parameters` and therefore in the digest, so
  # changing it without a version bump is caught.
  class DailyBloodPressureSummary < Derivation::Algorithm
    KEY = "daily_blood_pressure_summary"
    VERSION = 1

    # At least one usable reading. Deliberately not a statistical threshold —
    # deciding whether a day's worth of readings is *enough* is the evidence
    # gate's job in epic 003, not this algorithm's. Conflating the two would
    # hide a gate inside a derivation.
    MINIMUM_READINGS = 1

    def self.key = KEY
    def self.version = VERSION

    def self.parameters
      { aggregation: "median", minimum_readings: MINIMUM_READINGS }
    end

    def initialize(observations:, semantic_key:)
      @observations = observations
      @semantic_key = semantic_key
    end

    def call
      raw = @observations.to_a
      # STAT-002: only observed readings contribute. Missing ones are counted
      # in the denominator but never imputed — that is precisely the
      # distinction the raw/usable split exists to preserve.
      usable = raw.select { |o| o.observed? && o.value_numeric.present? }

      if usable.size < MINIMUM_READINGS
        return Outcome.new(
          value_numeric: nil, unit: nil, inputs: raw,
          usable_input_count: usable.size, raw_input_count: raw.size,
          status: "insufficient_input"
        )
      end

      Outcome.new(
        value_numeric: median(usable.map(&:value_numeric)),
        unit: usable.first.unit,
        inputs: usable,
        # STAT-004/005: raw sample count is not n. Three readings from one
        # cuff inflation are one analytical unit, and both counts are
        # persisted so the distinction survives into the artifact.
        usable_input_count: usable.size,
        raw_input_count: raw.size,
        status: "computed"
      )
    end

    private

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2

      if sorted.size.odd?
        sorted[mid]
      else
        # Exact arithmetic — these are BigDecimals, and a BP must not acquire
        # floating-point noise on its way through an average.
        (sorted[mid - 1] + sorted[mid]) / 2
      end
    end
  end
end
