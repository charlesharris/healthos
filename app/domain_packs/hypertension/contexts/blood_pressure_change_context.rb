# frozen_string_literal: true

module Hypertension
  # The reference ContextDefinition (epic 003-05).
  #
  # Emits both BIOLOGICAL and MEASUREMENT-BEHAVIOUR dimensions, deliberately
  # side by side. STAT-003 makes measurement behaviour first-class evidence
  # and STAT-007 requires instrumentation to be evaluated before biology — a
  # Context that emitted only blood pressure would make that ordering
  # impossible, because the comparison engine would have nothing to order
  # against.
  #
  # This definition computes and describes. It applies no gate and reaches no
  # conclusion: whether these dimensions support a claim is the Comparison's
  # job, and the two are kept apart so a gate cannot hide in a materializer.
  class BloodPressureChangeContext < Analysis::ContextDefinition
    KEY = "blood_pressure_change"
    VERSION = 1

    BIOLOGICAL_KEYS = %w[
      health.vital.blood_pressure.systolic
      health.vital.blood_pressure.diastolic
      health.vital.pulse
    ].freeze

    def self.key = KEY
    def self.version = VERSION
    def self.parameters = { biological_keys: BIOLOGICAL_KEYS }

    def materialize
      dimensions = BIOLOGICAL_KEYS.flat_map { |key| biological_dimensions(key) }
      dimensions += measurement_dimensions

      inputs = dimensions.flat_map { |d| Array(d.evidence) }.uniq

      Materialization.new(
        dimensions: dimensions,
        status: dimensions.any?(&:observed?) ? "materialized" : "insufficient_input",
        inputs: inputs,
        data_completeness: overall_completeness
      )
    end

    private

    def biological_dimensions(semantic_key)
      observations = observations_for(semantic_key)
      usable = observations.select { |o| o.observed? && o.value_numeric.present? }
      families = families_for(semantic_key)

      if usable.empty?
        # STAT-002: a dimension that could not be computed carries no value.
        # Emitted rather than omitted, so the Comparison can tell "we looked
        # and found nothing usable" from "we never looked".
        return [ Dimension.new(
          key: semantic_key, version: 1, quality_state: "expected_but_missing",
          window: window, evidence: observations, **families
        ) ]
      end

      values = usable.map(&:value_numeric)

      [
        Dimension.new(
          key: semantic_key, version: 1,
          value_numeric: median(values), unit: usable.first.unit,
          quality_state: "observed", window: window, evidence: usable, **families
        ),
        # Dispersion travels with central tendency. SC §29's robust
        # standardized effect needs a scale, and a Comparison that had to
        # recompute one would be reasoning about different inputs than the
        # Context recorded.
        Dimension.new(
          key: "#{semantic_key}.dispersion", version: 1,
          value_numeric: mad(values), unit: usable.first.unit,
          quality_state: usable.size >= 3 ? "observed" : "insufficient_input",
          window: window, evidence: usable,
          semantic_family: families[:semantic_family],
          source_family: families[:source_family],
          derivation_family: "dispersion"
        )
      ]
    end

    # STAT-003: measurement behaviour is data, not annotation.
    def measurement_dimensions
      completeness = Measurement::Completeness.call(
        subject: subject, semantic_key: BIOLOGICAL_KEYS.first, window: window
      )
      profile = Measurement::SourceProfile.for_window(
        subject: subject, semantic_key: BIOLOGICAL_KEYS.first, window: window
      )

      [
        Dimension.new(
          key: "health.measurement.completeness", version: 1,
          value_numeric: completeness.ratio,
          # An indeterminate completeness is not a low one. Reported as
          # unknown so a gate cannot read it as poor adherence.
          quality_state: completeness.indeterminate? ? "unknown" : "observed",
          unit: "ratio", window: window, evidence: [],
          # Diagnostics, not a value: STAT-021 wants the denominator visible
          # beside the ratio, and it must remain visible even when the ratio
          # itself is absent.
          details: { "usable" => completeness.usable,
                     "expected_total" => completeness.expected_total,
                     "missing_by_state" => completeness.missing_by_state,
                     "reason" => completeness.reason },
          **families_for("health.measurement.completeness")
        ),
        Dimension.new(
          key: "health.measurement.source_changed", version: 1,
          value_boolean: profile.indeterminate? ? nil : !profile.single_source?,
          quality_state: profile.indeterminate? ? "unknown" : "observed",
          window: window, evidence: [],
          details: { "source_count" => profile.source_mix.size,
                     "minority_share" => profile.minority_share,
                     "methods" => profile.method_mix.keys.sort },
          **families_for("health.measurement.source_changed")
        )
      ]
    end

    def observations_for(semantic_key)
      Observation
        .where(organization_id: subject.organization_id, subject_id: subject.id,
               semantic_key: semantic_key)
        .where(observed_at: window.first...window.last)
        .order(:observed_at)
        .to_a
    end

    def overall_completeness
      Measurement::Completeness.call(
        subject: subject, semantic_key: BIOLOGICAL_KEYS.first, window: window
      ).ratio
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    end

    def mad(values)
      med = median(values)
      median(values.map { |v| (v - med).abs })
    end
  end
end
