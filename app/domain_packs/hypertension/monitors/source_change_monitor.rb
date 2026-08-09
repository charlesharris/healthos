# frozen_string_literal: true

module Hypertension
  # Source/method-change monitor v1 (epic 002-10).
  #
  # ⚠️ NON-CLINICAL. Every threshold here is an engineering fixture chosen to
  # make synthetic scenarios fire, NOT a clinical parameter. HO §175 requires
  # review and promotion before pilot, and prototype-scope.md keeps that gate
  # closed. Nothing in this file has been reviewed by a clinician.
  #
  # HO §29 and STAT-003: what was recording is first-class evidence. A cuff
  # swapped for hand-typed numbers halfway through a window can produce every
  # appearance of a change in the subject while nothing about the subject has
  # changed at all, and STAT-007 therefore evaluates instrumentation BEFORE
  # biology. This monitor is the operational half of that ordering: it puts
  # the instrument change in front of a human at the same time as the apparent
  # change in the values.
  #
  # What this monitor does and does not claim:
  #
  #   It observes that a share of recent readings came from a source, or was
  #   recorded by a method, that the earlier window did not use, and says
  #   "a human may want to look."
  #
  #   It does NOT claim either instrument is more accurate, that the change
  #   explains anything else observed in the same period, or that the two
  #   sources are non-equivalent — equivalence is a declared property of the
  #   sources, not something a proportion can establish.
  #
  #   Above all it does NOT apply SC §11. The 30% cap and 50% suppression
  #   bands decide how much biological evidence survives an instrument change;
  #   they are governed contract defaults (STAT-044) belonging to the evidence
  #   gate in 003-15, and this monitor never approximates them. Its own
  #   fixture share sits well below both on purpose, so that surfacing a
  #   candidate for a human and rating evidence stay two separate decisions
  #   made in two separate places.
  class SourceChangeMonitor < Monitoring::Monitor
    include MonitorWindows

    KEY = "measurement_source_change"
    VERSION = 1
    DOMAIN_KEY = "hypertension"

    SEMANTIC_KEY = "health.vital.blood_pressure.systolic"

    def self.key = KEY
    def self.version = VERSION
    def self.domain_key = DOMAIN_KEY

    # NON-CLINICAL FIXTURES (HO §175).
    def self.default_parameters
      {
        recent_days: 7,
        baseline_days: 21,
        # Denominator floors before the monitor will look at all. Two windows
        # of one reading each always "changed source" and never mean anything.
        minimum_recent_readings: 3,
        minimum_baseline_readings: 7,
        # Share of recent readings from an unfamiliar source or method before
        # the change is worth a human's attention. NON-CLINICAL, and set
        # deliberately below any evidence band in SC §11 — a monitor surfaces
        # candidates, the gate rates them.
        notable_changed_share: 0.15,
        # Operational severity hint only, independent of evidence strength
        # (S2C-011).
        dominant_changed_share: 0.75
      }
    end

    def evaluate(subject:, as_of:)
      recent_window = window_ending(as_of, parameters[:recent_days])
      baseline_window = window_ending(recent_window.first, parameters[:baseline_days])

      recent = observed_readings(subject, SEMANTIC_KEY, recent_window)
      baseline = observed_readings(subject, SEMANTIC_KEY, baseline_window)

      if recent.size < parameters[:minimum_recent_readings] ||
         baseline.size < parameters[:minimum_baseline_readings]
        return Result.not_triggered(
          window: recent_window,
          details: { reason: "insufficient_points", recent: recent.size, baseline: baseline.size }
        )
      end

      recent_profile = Measurement::SourceProfile.build(recent)
      baseline_profile = Measurement::SourceProfile.build(baseline)
      comparison = Measurement::SourceProfile.compare(affected: recent_profile, baseline: baseline_profile)

      if comparison.indeterminate?
        # Cannot say the source changed and cannot say it did not. Reported as
        # insufficient rather than as no change, because a false "instrument
        # stable" is exactly what STAT-007's ordering exists to prevent.
        return Result.not_triggered(
          window: recent_window, details: { reason: "insufficient_points", profile: "indeterminate" }
        )
      end

      evaluate_shares(subject, recent_window, recent, baseline, recent_profile, baseline_profile,
                      comparison.changed_share)
    end

    private

    def evaluate_shares(subject, window, recent, baseline, recent_profile, baseline_profile, source_share)
      new_methods = recent_profile.method_mix.keys - baseline_profile.method_mix.keys
      method_share = Rational(
        recent.count { |reading| new_methods.include?(reading.recording_method) }, recent.size
      ).to_f

      dimensions = []
      dimensions << "source" if source_share >= parameters[:notable_changed_share]
      dimensions << "method" if method_share >= parameters[:notable_changed_share]

      if dimensions.empty?
        return Result.not_triggered(
          window: window,
          details: { reason: "below_threshold", source_share: source_share, method_share: method_share }
        )
      end

      triggered_result(subject, window, recent, baseline, recent_profile, baseline_profile,
                       source_share, method_share, new_methods, dimensions)
    end

    def triggered_result(subject, window, recent, baseline, recent_profile, baseline_profile,
                         source_share, method_share, new_methods, dimensions)
      Result.new(
        triggered: true,
        signal_type: "source_change",
        window: window,
        severity: [ source_share, method_share ].max >= parameters[:dominant_changed_share] ? "moderate" : "low",
        attributes: {
          "dimensions" => dimensions,
          # The proportion, never a bare boolean: SC §11's gate needs the
          # number, and "the source changed" throws away the only part of this
          # observation the gate can use.
          "changed_share" => source_share,
          "method_changed_share" => method_share,
          "recent_source_count" => recent_profile.source_mix.size,
          "baseline_source_count" => baseline_profile.source_mix.size,
          "recent_methods" => recent_profile.method_mix.keys.compact.sort,
          "baseline_methods" => baseline_profile.method_mix.keys.compact.sort,
          "new_methods" => new_methods.compact.sort,
          # Denominators travel with the observation (STAT-021); readings and
          # days are separate counts (STAT-004/005).
          "recent_reading_count" => recent.size,
          "baseline_reading_count" => baseline.size,
          "recent_day_count" => distinct_days(subject, recent),
          "baseline_day_count" => distinct_days(subject, baseline),
          "semantic_key" => SEMANTIC_KEY,
          # Explicit: this is descriptive, never causal (INV-34, STAT-001).
          # A source change that coincides with a value change is a
          # coincidence until something with a baseline says otherwise.
          "interpretation" => "descriptive_only"
        },
        # HO §34. Which dimension moved is part of the identity: a swapped
        # device and a switch to hand-entered readings are different events
        # and must not deduplicate onto each other.
        semantic_identity: "source_change:#{dimensions.join('+')}",
        details: { dimensions: dimensions, source_share: source_share, method_share: method_share }
      )
    end
  end
end
