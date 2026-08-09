# frozen_string_literal: true

require "rails_helper"

# Epic 002-07 to 002-11. HO §29 (measurement-behaviour signals), §30 (monitor
# engine), §31 (monitor configuration), §32 (MonitorEvaluation), §33/§34
# (Signal and idempotency); SC §11 (source change), SC §16 (differential
# missingness); S2C-001/002/003; STAT-001/003/004/005/021/044.
#
# The pack's job is to decide "is this worth a human looking at". It is
# emphatically NOT to decide "is this real evidence" — that is the evidence
# gate's in epic 003, and several specs below exist only to keep the two
# apart.
RSpec.describe "Hypertension monitor pack", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:cuff_source) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "BP cuff")
  end
  let!(:other_cuff_source) do
    Source.create!(organization: organization, key: "cuff_b", source_type: "device_cloud",
                   display_name: "Replacement cuff")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: cuff_source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:semantic_key) { "health.vital.blood_pressure.systolic" }
  let(:as_of) { Time.utc(2026, 3, 22, 12, 0) }

  # Observations are built directly rather than driven through ingestion: the
  # pipeline above them is already covered by the 001-05/08/09 specs, and what
  # is under test here is what a monitor makes of canonical state.
  def observe(days_ago:, value: 120, source: cuff_source, method: "device_automatic", nth: 0)
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope,
      source_record_id: "r-#{days_ago}-#{nth}-#{source.key}-#{method}",
      semantic_key: semantic_key, semantic_version: 1,
      value_numeric: value, unit: "mmHg",
      observed_at: as_of - days_ago.days + nth.minutes,
      normalized_at: Time.current, quality_state: "observed", recording_method: method,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def evaluate(monitor_key, configuration: nil)
    Monitoring::EvaluateMonitor.call(
      subject: subject_record, monitor_key: monitor_key, as_of: as_of, configuration: configuration
    )
  end

  PACK_MONITORS = %w[
    blood_pressure_threshold_excursion
    blood_pressure_variability_change
    measurement_frequency_change
    measurement_source_change
  ].freeze

  def pack_monitor_sources
    Rails.root.glob("app/domain_packs/hypertension/monitors/*.rb")
  end

  def code_without_comments(file)
    file.read.lines.reject { |line| line.strip.start_with?("#") }.join
  end

  describe "HO §30 registry" do
    it "registers every monitor in the pack" do
      expect(Monitoring::Monitor.all).to include(*PACK_MONITORS)
    end

    it "resolves each key to a monitor that declares its identity" do
      PACK_MONITORS.each do |key|
        monitor = Monitoring::Monitor.find(key)

        expect(monitor.key).to eq(key)
        expect(monitor.version).to eq(1)
        expect(monitor.domain_key).to eq("hypertension")
      end
    end
  end

  # ------------------------------------------------------------------
  # 002-07 Threshold excursion
  # ------------------------------------------------------------------
  describe "002-07 threshold-excursion monitor" do
    let(:monitor_key) { "blood_pressure_threshold_excursion" }

    it "fires when enough readings cross the fixture high edge" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 165 : 120) }

      result = evaluate(monitor_key)

      expect(result).to be_triggered
      expect(result.signal.signal_type).to eq("threshold_excursion")
      expect(result.signal.attributes_json["direction"]).to eq("above")
      expect(result.signal.attributes_json["excursion_count"]).to eq(3)
      expect(result.signal.attributes_json["threshold_mmhg"]).to eq(150)
    end

    it "fires below the fixture low edge with the opposite direction" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 80 : 120) }

      expect(evaluate(monitor_key).signal.attributes_json["direction"]).to eq("below")
    end

    it "does not fire on a single excursion" do
      (1..6).each { |d| observe(days_ago: d, value: d == 1 ? 165 : 120) }

      result = evaluate(monitor_key)

      expect(result).not_to be_triggered
      expect(result.evaluation.result).to eq("not_triggered")
      expect(result.evaluation.details["reason"]).to eq("below_threshold")
    end

    it "records insufficient_data rather than firing on too few readings" do
      (1..2).each { |d| observe(days_ago: d, value: 165) }

      result = evaluate(monitor_key)

      expect(result).not_to be_triggered
      expect(result.evaluation.result).to eq("insufficient_data")
    end

    # STAT-004/005: six readings from one afternoon and six across six days
    # are the same count and very different observations. Both travel.
    it "reports excursion days separately from excursion readings" do
      3.times { |nth| observe(days_ago: 1, value: 165, nth: nth) }
      (2..6).each { |d| observe(days_ago: d, value: 120) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["excursion_count"]).to eq(3)
      expect(attributes["excursion_days"]).to eq(1)
      expect(attributes["reading_count"]).to eq(8)
      expect(attributes["reading_days"]).to eq(6)
    end

    # STAT-001 / INV-34.
    it "labels its attributes descriptive rather than causal" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 165 : 120) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["interpretation"]).to eq("descriptive_only")
      expect(attributes.to_json).not_to match(/caused|because|due to/i)
    end

    it "records both edges so the quieter direction is not hidden" do
      (1..4).each { |d| observe(days_ago: d, value: 165) }
      (5..6).each { |d| observe(days_ago: d, value: 80) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["direction"]).to eq("above")
      expect(attributes["excursion_count_above"]).to eq(4)
      expect(attributes["excursion_count_below"]).to eq(2)
    end
  end

  # ------------------------------------------------------------------
  # 002-08 Variability change
  # ------------------------------------------------------------------
  describe "002-08 variability-change monitor" do
    let(:monitor_key) { "blood_pressure_variability_change" }

    def tight_baseline
      (8..20).each { |d| observe(days_ago: d, value: [ 118, 120, 122 ][d % 3]) }
    end

    def wide_baseline
      (8..21).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }
    end

    it "fires when the recent spread widens past the fixture threshold" do
      tight_baseline
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }

      result = evaluate(monitor_key)

      expect(result).to be_triggered
      expect(result.signal.signal_type).to eq("variability_change")
      expect(result.signal.attributes_json["direction"]).to eq("widening")
      # Baseline MAD 2, recent MAD 20.
      expect(result.signal.attributes_json["baseline_mad_mmhg"]).to eq("2.0")
      expect(result.signal.attributes_json["recent_mad_mmhg"]).to eq("20.0")
      expect(result.signal.attributes_json["mad_shift_mmhg"]).to eq("18.0")
    end

    it "fires in the narrowing direction too" do
      wide_baseline
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 120 : 121) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["direction"]).to eq("narrowing")
      expect(attributes["mad_shift_mmhg"]).to eq("-19.5")
    end

    it "does not fire when the spread is unchanged" do
      (8..21).each { |d| observe(days_ago: d, value: d.even? ? 118 : 122) }
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 118 : 122) }

      result = evaluate(monitor_key)

      expect(result).not_to be_triggered
      expect(result.evaluation.details["reason"]).to eq("below_threshold")
    end

    it "records insufficient_data rather than firing on a thin recent window" do
      tight_baseline
      (1..4).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }

      expect(evaluate(monitor_key).evaluation.result).to eq("insufficient_data")
    end

    # SC §29's robust scale, computed by platform core rather than reimplemented
    # in the pack.
    it "reports the median absolute deviation, not a standard deviation" do
      tight_baseline
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["scale"]).to eq("median_absolute_deviation")
      expect(attributes["recent_reading_count"]).to eq(6)
      expect(attributes["baseline_reading_count"]).to eq(13)
      expect(attributes["interpretation"]).to eq("descriptive_only")
    end
  end

  # ------------------------------------------------------------------
  # 002-09 Measurement frequency change
  # ------------------------------------------------------------------
  describe "002-09 measurement-frequency-change monitor" do
    let(:monitor_key) { "measurement_frequency_change" }

    def daily_baseline
      (8..28).each { |d| observe(days_ago: d) }
    end

    it "fires when the cadence falls past the fixture ratio" do
      daily_baseline
      observe(days_ago: 2)

      result = evaluate(monitor_key)

      expect(result).to be_triggered
      expect(result.signal.signal_type).to eq("measurement_frequency_change")
      expect(result.signal.attributes_json["direction"]).to eq("decrease")
      expect(result.signal.attributes_json["baseline_rate_per_day"]).to eq("1.0")
      expect(result.signal.attributes_json["retained_ratio"]).to eq("0.1429")
    end

    it "does not fire when the cadence holds up" do
      daily_baseline
      (1..6).each { |d| observe(days_ago: d) }

      result = evaluate(monitor_key)

      expect(result).not_to be_triggered
      expect(result.evaluation.details["reason"]).to eq("below_threshold")
    end

    # STAT-002 concerns inventing a biological zero from absence. Counting how
    # often a measurement actually happened is the opposite: measurement
    # behaviour is itself data (STAT-003, HO §29).
    it "treats a silent window as an observed cadence of zero, not as missing" do
      daily_baseline

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["recent_reading_count"]).to eq(0)
      expect(attributes["recent_rate_per_day"]).to eq("0.0")
      expect(attributes["retained_ratio"]).to eq("0.0")
    end

    it "records insufficient_data when there was never a cadence to lose" do
      (8..10).each { |d| observe(days_ago: d) }

      expect(evaluate(monitor_key).evaluation.result).to eq("insufficient_data")
    end

    # STAT-021: the rate is meaningless without the span it was computed over.
    it "carries both denominators the rates were computed from" do
      daily_baseline
      observe(days_ago: 2)

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["recent_window_days"]).to eq(7)
      expect(attributes["baseline_window_days"]).to eq(21)
      expect(attributes["baseline_reading_count"]).to eq(21)
      expect(attributes["recent_day_count"]).to eq(1)
    end

    # A subject who started measuring more is not "Monitoring interrupted",
    # which is the operational work this Signal feeds (HO §42).
    it "stays silent when the cadence rises" do
      (8..28).each { |d| observe(days_ago: d, nth: 0) }
      (1..6).each do |d|
        3.times { |nth| observe(days_ago: d, nth: nth) }
      end

      expect(evaluate(monitor_key)).not_to be_triggered
    end
  end

  # ------------------------------------------------------------------
  # 002-10 Source / method change
  # ------------------------------------------------------------------
  describe "002-10 source-change monitor" do
    let(:monitor_key) { "measurement_source_change" }

    def stable_instrument_baseline
      (8..28).each { |d| observe(days_ago: d, source: cuff_source, method: "device_automatic") }
    end

    it "fires when a share of recent readings comes from an unfamiliar source" do
      stable_instrument_baseline
      (1..3).each { |d| observe(days_ago: d, source: other_cuff_source) }
      (4..6).each { |d| observe(days_ago: d, source: cuff_source) }

      result = evaluate(monitor_key)

      expect(result).to be_triggered
      expect(result.signal.signal_type).to eq("source_change")
      expect(result.signal.attributes_json["dimensions"]).to eq([ "source" ])
      expect(result.signal.attributes_json["changed_share"]).to be_within(0.01).of(0.5)
    end

    it "fires on a recording-method change even when the source is unchanged" do
      stable_instrument_baseline
      (1..6).each { |d| observe(days_ago: d, source: cuff_source, method: "manual_entry") }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["dimensions"]).to eq([ "method" ])
      expect(attributes["changed_share"]).to eq(0.0)
      expect(attributes["method_changed_share"]).to eq(1.0)
      expect(attributes["new_methods"]).to eq([ "manual_entry" ])
    end

    it "names both dimensions when the instrument and the method both change" do
      stable_instrument_baseline
      (1..6).each { |d| observe(days_ago: d, source: other_cuff_source, method: "manual_entry") }

      result = evaluate(monitor_key)

      expect(result.signal.attributes_json["dimensions"]).to eq(%w[source method])
      expect(result.signal.severity).to eq("moderate")
    end

    it "does not fire when the instrument is stable" do
      stable_instrument_baseline
      (1..6).each { |d| observe(days_ago: d, source: cuff_source) }

      result = evaluate(monitor_key)

      expect(result).not_to be_triggered
      expect(result.evaluation.details["reason"]).to eq("below_threshold")
    end

    it "records insufficient_data rather than calling one reading a change" do
      (8..28).each { |d| observe(days_ago: d) }
      observe(days_ago: 1, source: other_cuff_source)

      expect(evaluate(monitor_key).evaluation.result).to eq("insufficient_data")
    end

    # SC §11's thresholds are proportions; a bare boolean cannot feed them.
    it "carries the proportion, never just a boolean" do
      stable_instrument_baseline
      (1..6).each { |d| observe(days_ago: d, source: other_cuff_source) }

      attributes = evaluate(monitor_key).signal.attributes_json

      expect(attributes["changed_share"]).to eq(1.0)
      expect(attributes["recent_source_count"]).to eq(1)
      expect(attributes["baseline_source_count"]).to eq(1)
      expect(attributes["interpretation"]).to eq("descriptive_only")
    end
  end

  # ------------------------------------------------------------------
  # HO §34 dedup identity
  # ------------------------------------------------------------------
  describe "HO §34 semantic event identity" do
    # A reversal is a genuinely different event. If direction were left out of
    # the identity, the second one would silently deduplicate onto the first
    # and the reversal would never reach a human.
    it "distinguishes opposite directions within the same window" do
      keys = %w[above below].map do |direction|
        Monitoring::Signal.deduplication_key_for(
          organization: organization, subject: subject_record,
          monitor_key: "blood_pressure_threshold_excursion", monitor_version: 1,
          window: [ as_of - 7.days, as_of ], semantic_identity: "threshold_excursion:#{direction}"
        )
      end

      expect(keys.uniq.size).to eq(2)
    end

    it "puts the direction in the excursion monitor's identity" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 80 : 120) }

      outcome = Hypertension::ThresholdExcursionMonitor.new
        .evaluate(subject: subject_record, as_of: as_of)

      expect(outcome.semantic_identity).to eq("threshold_excursion:below")
    end

    it "puts the direction in the variability monitor's identity" do
      (8..21).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 120 : 121) }

      outcome = Hypertension::VariabilityChangeMonitor.new
        .evaluate(subject: subject_record, as_of: as_of)

      expect(outcome.semantic_identity).to eq("variability_change:narrowing")
    end

    it "distinguishes an instrument swap from a switch to hand-entered readings" do
      (8..28).each { |d| observe(days_ago: d) }
      (1..6).each { |d| observe(days_ago: d, source: cuff_source, method: "manual_entry") }

      outcome = Hypertension::SourceChangeMonitor.new
        .evaluate(subject: subject_record, as_of: as_of)

      expect(outcome.semantic_identity).to eq("source_change:method")
    end

    it "returns the existing Signal on a repeated evaluation (S2C-002)" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 165 : 120) }

      first = evaluate("blood_pressure_threshold_excursion")
      second = evaluate("blood_pressure_threshold_excursion")

      expect(first).to be_created
      expect(second).not_to be_created
      expect(second.signal).to eq(first.signal)
      expect(Monitoring::Signal.count).to eq(1)
    end
  end

  # ------------------------------------------------------------------
  # 002-11 Per-organization configuration
  # ------------------------------------------------------------------
  describe "002-11 organization configuration (HO §31)" do
    def configure(monitor_key, parameters: {}, enabled: true)
      MonitorConfiguration.create!(
        organization: organization, domain_key: "hypertension",
        monitor_key: monitor_key, monitor_version: 1,
        enabled: enabled, parameters: parameters
      )
    end

    it "honours an overridden excursion threshold" do
      (1..6).each { |d| observe(days_ago: d, value: d <= 3 ? 155 : 120) }
      config = configure("blood_pressure_threshold_excursion", parameters: { "high_mmhg" => 170 })

      result = evaluate("blood_pressure_threshold_excursion", configuration: config)

      # 155 clears the pack default of 150 and not this organization's 170:
      # customer policy sets thresholds without changing code identity.
      expect(result).not_to be_triggered
    end

    it "honours an overridden variability threshold" do
      (8..20).each { |d| observe(days_ago: d, value: [ 118, 120, 122 ][d % 3]) }
      (1..6).each { |d| observe(days_ago: d, value: d.even? ? 100 : 140) }
      config = configure("blood_pressure_variability_change",
                         parameters: { "mad_shift_threshold_mmhg" => 25 })

      # An 18 mmHg MAD shift clears the pack default of 5 and not this
      # organization's 25.
      expect(evaluate("blood_pressure_variability_change", configuration: config)).not_to be_triggered
    end

    it "honours an overridden cadence ratio" do
      (8..28).each { |d| observe(days_ago: d) }
      (1..4).each { |d| observe(days_ago: d) }
      config = configure("measurement_frequency_change",
                         parameters: { "cadence_retained_ratio" => 0.4 })

      # A retained ratio of ~0.57 trips the pack default of 0.66 and not 0.4.
      expect(evaluate("measurement_frequency_change", configuration: config)).not_to be_triggered
    end

    it "honours an overridden source-change share" do
      (8..28).each { |d| observe(days_ago: d) }
      (1..2).each { |d| observe(days_ago: d, source: other_cuff_source) }
      (3..6).each { |d| observe(days_ago: d, source: cuff_source) }
      config = configure("measurement_source_change", parameters: { "notable_changed_share" => 0.9 })

      expect(evaluate("measurement_source_change", configuration: config)).not_to be_triggered
    end

    it "skips a disabled monitor and records that it skipped" do
      PACK_MONITORS.each do |key|
        config = configure(key, enabled: false)

        result = evaluate(key, configuration: config)

        expect(result).not_to be_triggered
        expect(MonitorEvaluation.last.result).to eq("skipped")
      end
    end

    it "merges organization parameters over pack defaults" do
      config = configure("blood_pressure_threshold_excursion", parameters: { "high_mmhg" => 170 })

      expect(config.effective_parameters[:high_mmhg]).to eq(170)
      expect(config.effective_parameters[:low_mmhg])
        .to eq(Hypertension::ThresholdExcursionMonitor.default_parameters[:low_mmhg])
    end

    # HO §31: configuration "lets customer policy specify thresholds without
    # changing code definition identity." Every Signal is stamped with the
    # monitor digest (INV-6), and an organization's policy must not move it.
    it "does not change the monitor digest" do
      before_digest = Hypertension::ThresholdExcursionMonitor.digest
      configure("blood_pressure_threshold_excursion", parameters: { "high_mmhg" => 170 })

      expect(Hypertension::ThresholdExcursionMonitor.digest).to eq(before_digest)
    end
  end

  # ------------------------------------------------------------------
  # Governance guards
  # ------------------------------------------------------------------
  describe "STAT-044 governed values stay out of the pack" do
    # SC §11's 30/50 source-change bands and SC §15's 40/60/80 completeness
    # bands decide how much evidence survives. They belong to the evidence
    # gates in 003-14/003-15. A monitor that restated them would quietly
    # become a second, unreviewed copy of the statistical contract.
    it "encodes none of the contract's evidence bands" do
      offenders = pack_monitor_sources.select do |file|
        code_without_comments(file).match?(/\b(0\.3|0\.5|0\.25|25|30|40|50|60|80)\b/)
      end

      expect(offenders).to be_empty,
        "Evidence bands belong to the gates in epic 003: #{offenders.map(&:basename).join(', ')}"
    end

    # Every threshold a monitor compares against must be a named parameter, so
    # that it lands in `default_parameters`, therefore in the monitor digest,
    # therefore in CI's drift check — and so an organization can override it.
    it "compares against named parameters, never bare numbers" do
      offenders = pack_monitor_sources.select do |file|
        # `(?<!=)` so a hash rocket followed by a literal is not mistaken for
        # a comparison.
        code_without_comments(file).match?(/(?<!=)[<>]=?\s*-?\d/)
      end

      expect(offenders).to be_empty,
        "Thresholds must be digested parameters: #{offenders.map(&:basename).join(', ')}"
    end

    it "labels every threshold NON-CLINICAL against HO §175" do
      thresholded = pack_monitor_sources.reject { |file| file.basename.to_s == "monitor_windows.rb" }

      thresholded.each do |file|
        expect(file.read).to include("NON-CLINICAL"), "#{file.basename} must declare its fixtures"
        expect(file.read).to include("§175"), "#{file.basename} must cite HO §175"
      end
    end

    it "keeps every fixture in default_parameters, where the digest sees it" do
      PACK_MONITORS.each do |key|
        monitor = Monitoring::Monitor.find(key)

        expect(monitor.default_parameters).not_to be_empty
        expect(monitor.digest).to eq(
          Definitions::DefinitionDigest.compute(
            key: monitor.key, version: monitor.version, parameters: monitor.default_parameters
          )
        )
      end
    end

    # HO §31: "clinical threshold defaults should not be invented by platform
    # core." Core ships none; the pack owns all of them.
    it "leaves platform core with no defaults of its own" do
      expect(Monitoring::Monitor.default_parameters).to eq({})
    end
  end
end
