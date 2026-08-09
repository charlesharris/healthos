# frozen_string_literal: true

require "rails_helper"

# Epic 003-06 and 003-08. HO §56–57; SC §19–22; STAT-015/016/017/021.
#
# A BaselineDefinition answers "what counts as this subject's normal, and is
# there enough of it to say so". SC §20 is emphatic that there is no universal
# `normal` — hence a definition per baseline type, versioned and digested, and
# never a bare 30-day average hidden in a comparison.
RSpec.describe "Baselines::Definition", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:source) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "Cuff")
  end

  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:semantic_key) { "health.vital.blood_pressure.systolic" }
  let(:as_of) { Time.utc(2026, 3, 22, 12, 0) }

  # `days_ago` is relative to as_of's local midnight, matching the half-open
  # day-aligned windows the definition uses.
  # `at_hour` varies because the normalization-identity index is unique on
  # (raw_envelope, semantic_key, version, normalizer_version, observed_at) —
  # two readings on the same day must genuinely differ in time, as they would.
  def record_day(days_ago, value: 120, quality_state: "observed",
                 recording_method: "device_automatic", at_hour: 9)
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r-#{days_ago}-#{value}-#{SecureRandom.hex(3)}",
      semantic_key: semantic_key, semantic_version: 1,
      observed_at: as_of.beginning_of_day - days_ago.days + at_hour.hours,
      value_numeric: quality_state == "observed" ? value : nil,
      unit: quality_state == "observed" ? "mmHg" : nil,
      normalized_at: Time.current, quality_state: quality_state,
      recording_method: recording_method,
      normalizer_key: "spec", normalizer_version: 1
    )
  end

  def build(**overrides)
    Baselines::PersonalRecent.new(
      subject: subject_record, semantic_key: semantic_key, as_of: as_of, **overrides
    ).build
  end

  describe "the definition is versioned and digested (HO §56)" do
    it "identifies itself" do
      expect(Baselines::PersonalRecent.key).to eq("personal_recent")
      expect(Baselines::PersonalRecent.version).to be_a(Integer)
      expect(Baselines::PersonalRecent.baseline_type).to eq("personal_recent")
      expect(Baselines::PersonalRecent.digest).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is resolvable by key" do
      expect(Baselines::Definition.find("personal_recent")).to eq(Baselines::PersonalRecent)
    end

    it "refuses an unknown key rather than returning nil" do
      expect { Baselines::Definition.find("wishful_thinking") }.to raise_error(ArgumentError)
    end

    # HO §25: a behaviour change without a version bump must be detectable.
    # The sufficiency thresholds decide what the baseline IS, so they belong
    # in the digest — a definition that silently started accepting 5 days
    # instead of 10 would otherwise keep its identity.
    it "digests the sufficiency thresholds" do
      expect(Baselines::PersonalRecent.parameters).to include(
        "minimum_usable_units", "target_usable_units",
        "minimum_calendar_span_days", "target_calendar_span_days"
      )
    end

    # STAT-044: the numbers come from governed config, not from the class.
    it "takes its thresholds from the statistical configuration" do
      config = Analysis::StatisticalConfig.instance

      expect(Baselines::PersonalRecent.minimum_usable_units)
        .to eq(config.baseline("minimum_usable_units"))
      expect(Baselines::PersonalRecent.target_usable_units)
        .to eq(config.baseline("target_usable_units"))
    end
  end

  describe "STAT-016/017 maturity" do
    it "is immature below the minimum" do
      5.times { |i| record_day(i + 1) }

      result = build
      expect(result.maturity).to eq("immature")
      expect(result.usable_units).to eq(5)
    end

    # 12 usable days spread across 16 calendar days: clears the 10-unit AND
    # 14-day minimums, short of the 21/28 target. Written this way because
    # twelve CONSECUTIVE days does not qualify — it spans only 12 days — and
    # that is the rule working, not a fixture inconvenience.
    it "is partial at the minimum but below the target" do
      ([ 16 ] + (1..11).to_a).each { |days_ago| record_day(days_ago) }

      result = build
      expect(result.maturity).to eq("partial")
      expect(result.usable_units).to eq(12)
      expect(result.calendar_span_days).to eq(16)
    end

    it "is mature at the target" do
      ([ 28 ] + (1..21).to_a).each { |days_ago| record_day(days_ago) }

      result = build
      expect(result.maturity).to eq("mature")
      expect(result.usable_units).to be >= 21
      expect(result.calendar_span_days).to be >= 28
    end

    # SC §21 stores units AND span so a burst of measurement cannot pass for
    # sustained history. Twenty-five readings over three days is not a month.
    it "does not let a burst of readings reach maturity" do
      25.times do |i|
        Observation.create!(
          organization: organization, subject: subject_record, source: source,
          raw_envelope: envelope, source_record_id: "burst-#{i}",
          semantic_key: semantic_key, semantic_version: 1,
          observed_at: as_of.beginning_of_day - 2.days + (i * 20).minutes,
          value_numeric: 120, unit: "mmHg", quality_state: "observed",
          normalized_at: Time.current, recording_method: "device_automatic",
          normalizer_key: "spec", normalizer_version: 1
        )
      end

      result = build
      expect(result.usable_units).to eq(1)
      expect(result.maturity).to eq("immature")
    end
  end

  describe "STAT-021 denominators" do
    it "reports usable units, raw readings and calendar span separately" do
      12.times { |i| record_day(i + 1) }
      # Two extra readings on one day. STAT-005: not two more units.
      record_day(1, value: 124, at_hour: 13)
      record_day(1, value: 118, at_hour: 18)

      result = build

      expect(result.usable_units).to eq(12)
      expect(result.raw_reading_count).to eq(14)
      expect(result.calendar_span_days).to eq(12)
    end

    # STAT-002: a missing day is missing, never zero, and never silently
    # dropped from the record of what was looked at.
    it "excludes non-observed readings from units without imputing them" do
      8.times { |i| record_day(i + 1) }
      3.times { |i| record_day(i + 9, quality_state: "expected_but_missing") }

      result = build

      expect(result.usable_units).to eq(8)
      expect(result.missing_by_state).to include("expected_but_missing" => 3)
      expect(result.maturity).to eq("immature")
    end
  end

  describe "the value it produces" do
    # SC §29's robust comparison needs a centre and a scale, and both must
    # come from the same inputs the baseline recorded.
    it "summarises by median and MAD over daily values" do
      [ 100, 102, 104, 106, 108, 110, 112, 114, 116, 118, 120, 122 ].each_with_index do |value, i|
        record_day(i + 1, value: value)
      end

      result = build

      expect(result.central_value).to eq(111)
      expect(result.dispersion).to be_present
      expect(result.unit).to eq("mmHg")
    end

    # SC §22's aggregation rule. Three readings on a day are one day's value,
    # or an enthusiastic afternoon outvotes a fortnight (STAT-005).
    it "collapses a day's readings to one value before summarising" do
      record_day(1, value: 200, at_hour: 8)
      record_day(1, value: 200, at_hour: 12)
      record_day(1, value: 200, at_hour: 16)
      (2..12).each { |i| record_day(i, value: 100) }

      result = build

      # 11 days at 100 and one at 200: the median is 100, not dragged up by
      # the three copies.
      expect(result.central_value).to eq(100)
      expect(result.usable_units).to eq(12)
    end
  end

  describe "the window" do
    it "is day-aligned, half-open, and ends where the affected window begins" do
      result = build(ends_at: as_of - 7.days)

      expect(result.window.first).to eq((as_of - 7.days).beginning_of_day - 28.days)
      expect(result.window.last).to eq((as_of - 7.days).beginning_of_day)
    end

    # Half-open, so the baseline and the affected window it abuts cannot both
    # count the same reading.
    it "excludes a reading exactly on the closing boundary" do
      boundary = (as_of - 7.days).beginning_of_day
      Observation.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, source_record_id: "boundary",
        semantic_key: semantic_key, semantic_version: 1,
        observed_at: boundary, value_numeric: 200, unit: "mmHg",
        normalized_at: Time.current,
        quality_state: "observed", recording_method: "device_automatic",
        normalizer_key: "spec", normalizer_version: 1
      )

      result = build(ends_at: as_of - 7.days)
      expect(result.usable_units).to eq(0)
    end
  end

  describe "SC §22 source compatibility" do
    # The definition records what the baseline was measured WITH. A comparison
    # that cannot see the baseline's source mix cannot apply STAT-008/009, and
    # would rate an instrument change as biology.
    it "carries a source summary" do
      8.times { |i| record_day(i + 1) }
      4.times { |i| record_day(i + 9, recording_method: "manual_entry") }

      result = build

      expect(result.source_summary["method_mix"]).to include(
        "device_automatic" => 8, "manual_entry" => 4
      )
    end
  end

  describe "SC §19 eligibility" do
    # A definition that will happily reach back a year to find ten days is not
    # describing "recent". Eligibility is stated rather than implied by
    # whatever data happens to exist.
    it "does not look outside its eligible range for units" do
      5.times { |i| record_day(i + 1) }
      10.times { |i| record_day(i + 200) }

      result = build

      expect(result.usable_units).to eq(5)
      expect(result.maturity).to eq("immature")
    end
  end

  describe "INV-3 lineage" do
    it "returns the exact input records" do
      3.times { |i| record_day(i + 1) }

      result = build

      expect(result.inputs.size).to eq(3)
      expect(result.inputs).to all(be_a(Observation))
    end
  end
end
