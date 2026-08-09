# frozen_string_literal: true

require "rails_helper"

# Epic 002-04 to 002-06. HO §20, §29; STAT-003, STAT-007.
#
# HO §29: "these are first-class evidence. They are not merely data-quality
# annotations." That is the claim these specs are protecting.
RSpec.describe "Measurement behaviour signals", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:cuff_source) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "BP cuff")
  end
  let!(:manual_source) do
    Source.create!(organization: organization, key: "manual", source_type: "manual",
                   display_name: "Manual entry")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: cuff_source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:key) { "health.vital.blood_pressure.systolic" }
  let(:as_of) { Time.utc(2026, 3, 22, 12, 0) }

  def observe(days_ago:, value: 130, source: cuff_source, method: "device_automatic",
              quality_state: "observed")
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r-#{days_ago}-#{method}-#{source.key}",
      semantic_key: key, semantic_version: 1,
      value_numeric: quality_state == "observed" ? value : nil,
      unit: quality_state == "observed" ? "mmHg" : nil,
      observed_at: as_of - days_ago.days, normalized_at: Time.current,
      quality_state: quality_state, recording_method: method,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  describe "frequency (HO §29)" do
    it "reports measurements per day over the window" do
      3.times { |i| observe(days_ago: i + 1) }

      outcome = Derivation::MeasurementBehavior::Frequency.new(
        observations: Observation.all, window: [ as_of - 6.days, as_of ], subject: subject_record
      ).call

      # 3 readings over a 7-day window, rounded to 4dp as the algorithm does.
      expect(outcome.value_numeric).to eq(BigDecimal("0.4286"))
      expect(outcome.unit).to eq("measurements_per_day")
    end

    # Frequency and completeness answer different questions. A subject
    # measuring three times daily against a once-daily protocol has 100%
    # completeness and a frequency of 3; a subject with no expectation model
    # has no completeness at all but still has a frequency.
    it "is computable without an expectation model" do
      2.times { |i| observe(days_ago: i + 1) }

      outcome = Derivation::MeasurementBehavior::Frequency.new(
        observations: Observation.all, window: [ as_of - 1.day, as_of ], subject: subject_record
      ).call

      expect(outcome.status).to eq("computed")
    end

    it "counts only observed readings" do
      observe(days_ago: 1)
      observe(days_ago: 2, quality_state: "device_not_reporting")

      outcome = Derivation::MeasurementBehavior::Frequency.new(
        observations: Observation.all, window: [ as_of - 1.day, as_of ], subject: subject_record
      ).call

      # STAT-002: a gap is not a reading. It appears in raw_input_count, never
      # in the numerator.
      expect(outcome.usable_input_count).to eq(1)
      expect(outcome.raw_input_count).to eq(2)
    end
  end

  describe "days since last (HO §29)" do
    it "measures the gap to the most recent observed reading" do
      observe(days_ago: 5)

      outcome = Derivation::MeasurementBehavior::DaysSinceLast.new(
        observations: Observation.all, as_of: as_of, subject: subject_record
      ).call

      expect(outcome.value_numeric).to eq(5)
    end

    # "Infinity days since last" is a different claim from "no reading in this
    # window", and a numeric stand-in would be zero-imputation's cousin
    # (STAT-002).
    it "reports insufficient_input rather than a large number when nothing was recorded" do
      outcome = Derivation::MeasurementBehavior::DaysSinceLast.new(
        observations: Observation.none, as_of: as_of, subject: subject_record
      ).call

      expect(outcome.status).to eq("insufficient_input")
      expect(outcome.value_numeric).to be_nil
    end

    # Completeness over a 14-day window looks similar whether the gap is
    # spread out or is a solid week ending yesterday. This is what separates
    # them.
    it "distinguishes a recent silence from scattered gaps" do
      observe(days_ago: 10)
      observe(days_ago: 12)

      outcome = Derivation::MeasurementBehavior::DaysSinceLast.new(
        observations: Observation.all, as_of: as_of, subject: subject_record
      ).call

      expect(outcome.value_numeric).to eq(10)
    end
  end

  describe "manual entry frequency (STAT-003, SC §16)" do
    it "reports the share of readings entered by a person" do
      2.times { |i| observe(days_ago: i + 1, method: "device_automatic") }
      2.times { |i| observe(days_ago: i + 3, method: "manual_entry", source: manual_source) }

      outcome = Derivation::MeasurementBehavior::ManualEntryFrequency.new(
        observations: Observation.all
      ).call

      expect(outcome.value_numeric).to eq(BigDecimal("0.5"))
    end

    it "treats transcription as manual, since a person mediated the value" do
      observe(days_ago: 1, method: "device_manual_transcription")

      outcome = Derivation::MeasurementBehavior::ManualEntryFrequency.new(
        observations: Observation.all
      ).call

      expect(outcome.value_numeric).to eq(1)
    end
  end

  describe "variability (SC §29)" do
    # MAD rather than SD: one mis-cuffed 220 inflates a standard deviation far
    # more than it does a median absolute deviation.
    it "uses a robust scale that resists a single outlier" do
      [ 120, 122, 124, 126, 220 ].each_with_index { |v, i| observe(days_ago: i + 1, value: v) }

      outcome = Derivation::MeasurementBehavior::Variability.new(
        observations: Observation.all.to_a
      ).call

      # Median 124; deviations sorted [0, 2, 2, 4, 96], so MAD = 2.
      # The standard deviation of the same readings is roughly 43 — the
      # outlier moves it by an order of magnitude and barely moves the MAD.
      expect(outcome.value_numeric).to eq(2)
    end

    # SC §29: "if scale is zero or too poorly estimated, omit the standardized
    # value." Too few readings is exactly that case.
    it "reports insufficient_input below the minimum reading count" do
      2.times { |i| observe(days_ago: i + 1) }

      outcome = Derivation::MeasurementBehavior::Variability.new(
        observations: Observation.all.to_a
      ).call

      expect(outcome.status).to eq("insufficient_input")
      expect(outcome.value_numeric).to be_nil
    end
  end

  describe "source profile (HO §20, STAT-007)" do
    it "reports the source mix rather than a boolean" do
      3.times { |i| observe(days_ago: i + 1, source: cuff_source) }
      1.times { observe(days_ago: 5, source: manual_source, method: "manual_entry") }

      profile = Measurement::SourceProfile.for_window(
        subject: subject_record, semantic_key: key, window: [ as_of - 7.days, as_of ]
      )

      # "The source changed" is far less useful than the proportion, because
      # SC §11's thresholds are proportions.
      expect(profile.source_mix.size).to eq(2)
      expect(profile.minority_share).to be_within(0.01).of(0.25)
      expect(profile).not_to be_single_source
    end

    # SC §11's input: how much of the affected window came from somewhere the
    # baseline did not.
    it "computes the changed share between affected and baseline windows" do
      # Baseline: all cuff.
      (10..16).each { |d| observe(days_ago: d, source: cuff_source) }
      # Affected: half manual.
      (1..2).each { |d| observe(days_ago: d, source: cuff_source) }
      (3..4).each { |d| observe(days_ago: d, source: manual_source, method: "manual_entry") }

      affected = Measurement::SourceProfile.for_window(
        subject: subject_record, semantic_key: key, window: [ as_of - 7.days, as_of ]
      )
      baseline = Measurement::SourceProfile.for_window(
        subject: subject_record, semantic_key: key, window: [ as_of - 20.days, as_of - 8.days ]
      )

      comparison = Measurement::SourceProfile.compare(affected: affected, baseline: baseline)

      expect(comparison.changed_share).to be_within(0.01).of(0.5)
    end

    # A false "no change" would let a biological reading through unqualified,
    # which is what STAT-007's ordering exists to prevent.
    it "reports indeterminate rather than no-change when a window is empty" do
      affected = Measurement::SourceProfile.build([])
      baseline = Measurement::SourceProfile.build([])

      comparison = Measurement::SourceProfile.compare(affected: affected, baseline: baseline)

      expect(comparison).to be_indeterminate
      expect(comparison.changed_share).to be_nil
    end

    # The 30% and 50% thresholds are SC §11's and belong to the evidence gate
    # in 003-15. Putting them here would bury governed values in a derivation.
    it "encodes no threshold of its own" do
      source = Rails.root.join("app/services/measurement/source_profile.rb").read
      code = source.lines.reject { |l| l.strip.start_with?("#") }.join

      expect(code).not_to match(/0\.3|0\.5|30|50/)
    end
  end

  describe "source change derivation (HO §29)" do
    it "carries the proportion alongside the boolean" do
      (10..16).each { |d| observe(days_ago: d, source: cuff_source) }
      (1..4).each { |d| observe(days_ago: d, source: manual_source, method: "manual_entry") }

      outcome = Derivation::SourceChange.new(
        subject: subject_record, semantic_key: key,
        affected_window: [ as_of - 7.days, as_of ],
        baseline_window: [ as_of - 20.days, as_of - 8.days ]
      ).call

      expect(outcome.value_json["changed"]).to be(true)
      # A bare true/false cannot feed SC §11's proportional thresholds.
      expect(outcome.value_json["changed_share"]).to eq(1.0)
      expect(outcome.value_json["method_changed"]).to be(true)
    end

    it "reports no change when the source is stable" do
      (10..16).each { |d| observe(days_ago: d, source: cuff_source) }
      (1..4).each { |d| observe(days_ago: d, source: cuff_source) }

      outcome = Derivation::SourceChange.new(
        subject: subject_record, semantic_key: key,
        affected_window: [ as_of - 7.days, as_of ],
        baseline_window: [ as_of - 20.days, as_of - 8.days ]
      ).call

      expect(outcome.value_json["changed"]).to be(false)
      expect(outcome.value_json["changed_share"]).to eq(0.0)
    end
  end

  describe "device transitions (HO §20)" do
    it "answers which devices were recording across a window" do
      old_cuff = Device.create!(organization: organization, source: cuff_source,
                                subject: subject_record, external_id: "cuff-old",
                                active_from: as_of - 60.days, active_to: as_of - 5.days)
      new_cuff = Device.create!(organization: organization, source: cuff_source,
                                subject: subject_record, external_id: "cuff-new",
                                active_from: as_of - 6.days)

      overlapping = Device.active_during(as_of - 7.days, as_of)

      # Two devices across one window is the transition STAT-008 cares about.
      expect(overlapping).to contain_exactly(old_cuff, new_cuff)
    end
  end
end
