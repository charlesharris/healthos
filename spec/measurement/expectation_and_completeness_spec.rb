# frozen_string_literal: true

require "rails_helper"

# Epic 002-01 to 002-03. HO §27–29; SC §13–14; STAT-002, STAT-005, STAT-010,
# STAT-011.
RSpec.describe "Measurement expectation and completeness", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "America/New_York") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:systolic_key) { "health.vital.blood_pressure.systolic" }

  # Exactly Monday 2 March to Sunday 8 March in the SUBJECT'S timezone —
  # seven local days. Note the end bound is 03:59 UTC, not 04:59: US DST
  # begins on 8 March 2026, so the last local day is an hour shorter in UTC
  # terms. Getting this wrong silently adds an eighth day, which is exactly
  # the class of error HO §121 makes a required regression case.
  # Half-open: local midnight 2 March to local midnight 9 March, i.e. the
  # seven days 2-8 March. The end bound is 04:00 UTC, not 05:00, because US
  # DST begins on 8 March 2026 and local midnight moves an hour earlier in UTC
  # terms — HO §121's regression case, in the fixture itself.
  let(:window) { [ Time.utc(2026, 3, 2, 5, 0), Time.utc(2026, 3, 9, 4, 0) ] }

  def observe(date_str, quality_state: "observed", hour: 14)
    at = ActiveSupport::TimeZone["America/New_York"].parse("#{date_str} #{hour}:00")
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r-#{date_str}-#{hour}",
      semantic_key: systolic_key, semantic_version: 1,
      value_numeric: quality_state == "observed" ? 130 : nil,
      unit: quality_state == "observed" ? "mmHg" : nil,
      observed_at: at, normalized_at: Time.current, quality_state: quality_state,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def completeness = Measurement::Completeness.call(
    subject: subject_record, semantic_key: systolic_key, window: window
  )

  describe "HO §27 three-state output" do
    # Two states would be a lie. "We do not know whether a reading was
    # expected" is a different claim from "no reading was expected", and
    # collapsing them either fabricates gaps or hides them.
    it "distinguishes expected, not_expected and unknown" do
      states = Measurement::Expectation::Opportunity.members
      expect(states).to include(:state)

      weekday = Measurement::WeekdaySchedule.new
      result = weekday.opportunities(subject: subject_record, window: window, semantic_key: systolic_key)

      expect(result.opportunities.map(&:state).uniq).to contain_exactly(:expected, :not_expected)
    end

    # SC §13's worked example: "BP protocol expects 5 measurement days/week."
    it "treats weekend days as not_expected, so they are not gaps" do
      result = Measurement::WeekdaySchedule.new
        .opportunities(subject: subject_record, window: window, semantic_key: systolic_key)

      expect(result.expected_days).to eq(5)
      expect(result.not_expected_days).to eq(2)
      # The denominator counts only what was genuinely expected.
      expect(result.expected_total).to eq(5)
    end

    it "returns unknown when no expectation model is declared" do
      result = Measurement::Expectation.for_semantic("health.measurement.frequency")
        .opportunities(subject: subject_record, window: window, semantic_key: "health.measurement.frequency")

      expect(result.opportunities.map(&:state).uniq).to eq([ :unknown ])
      expect(result).to be_indeterminate
      expect(result.expected_total).to eq(0)
    end

    it "resolves the declared model from the semantic registry" do
      # The BP keys declare expected_measurement: daily_opportunity.
      expectation = Measurement::Expectation.for_semantic(systolic_key)

      expect(expectation).to be_a(Measurement::DailyOpportunity)
    end
  end

  describe "SC §14 completeness with explicit denominator (STAT-011)" do
    it "reports usable over expected, not a bare ratio" do
      %w[2026-03-02 2026-03-03 2026-03-04 2026-03-05 2026-03-06].each { |d| observe(d) }
      # 5 of 7 local days (daily_opportunity expects one reading every day).

      result = completeness

      expect(result.usable).to eq(5)
      expect(result.expected_total).to eq(7)
      expect(result.ratio).to be_within(0.001).of(0.714)
      expect(result.to_s).to eq("71.4% (5/7)")
    end

    # 70% of ten days and 70% of a hundred are not the same evidence. A ratio
    # without its denominator cannot distinguish them, which is why STAT-011
    # requires both.
    it "carries the denominator alongside the ratio" do
      observe("2026-03-02")

      expect(completeness.expected_total).to eq(7)
      expect(completeness.percentage).to be_within(0.1).of(14.3)
    end

    # STAT-005: three readings on one day are one day's worth of completeness.
    # Counting observations would let one enthusiastic day mask a week of
    # silence.
    it "counts distinct days, not observations" do
      observe("2026-03-02", hour: 8)
      observe("2026-03-02", hour: 14)
      observe("2026-03-02", hour: 20)

      expect(completeness.usable).to eq(1)
    end

    # STAT-002: a missing reading is not a zero-valued one. It reduces
    # completeness and contributes no value.
    it "excludes missing readings from the numerator while counting the day" do
      observe("2026-03-02")
      observe("2026-03-03", quality_state: "device_not_reporting")

      result = completeness

      expect(result.usable).to eq(1)
      expect(result.expected_total).to eq(7)
      expect(result.missing_by_state).to include("device_not_reporting" => 1)
    end

    # The ten-state taxonomy survives into the completeness report, so an
    # instrumentation gap stays distinguishable from a behavioural one
    # (STAT-003, STAT-010).
    it "reports missingness by state rather than as one total" do
      observe("2026-03-02", quality_state: "device_not_reporting")
      observe("2026-03-03", quality_state: "manual_entry_absent")
      observe("2026-03-04", quality_state: "invalid_measurement")

      expect(completeness.missing_by_state).to eq(
        "device_not_reporting" => 1, "manual_entry_absent" => 1, "invalid_measurement" => 1
      )
    end
  end

  describe "indeterminate completeness" do
    # A ratio of 0 would say "they measured nothing"; a ratio of 1 would say
    # "they measured everything expected". Both are assertions we cannot make
    # without an expectation model, so neither is reported.
    it "returns no ratio when no expectation model is declared" do
      result = Measurement::Completeness.call(
        subject: subject_record, semantic_key: "health.measurement.frequency", window: window
      )

      expect(result).to be_indeterminate
      expect(result.ratio).to be_nil
      expect(result.percentage).to be_nil
      expect(result.reason).to eq("no_expectation_model")
    end

    it "returns no ratio for an event-driven dimension" do
      expectation = Measurement::EventDriven.new
      result = expectation.opportunities(
        subject: subject_record, window: window, semantic_key: systolic_key
      )

      # SC §13: event-driven has no daily completeness denominator. Not the
      # same as unknown — here we positively know nothing was expected.
      expect(result.expected_total).to eq(0)
      expect(result).not_to be_indeterminate
    end
  end

  describe "subject-local day boundaries (HO §121)" do
    it "attributes an evening reading to the subject's local day" do
      # 2026-03-03 01:00 UTC is 2026-03-02 20:00 in New York.
      Observation.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, source_record_id: "late",
        semantic_key: systolic_key, semantic_version: 1,
        value_numeric: 130, unit: "mmHg",
        observed_at: Time.utc(2026, 3, 3, 1, 0), normalized_at: Time.current,
        normalizer_key: "synthetic_bp_json", normalizer_version: 1
      )

      # Counted once, on 2026-03-02 local. A UTC-based grouping would place it
      # on the 3rd and, if the 2nd also had a reading, double-count the day.
      expect(completeness.usable).to eq(1)
    end
  end
end
