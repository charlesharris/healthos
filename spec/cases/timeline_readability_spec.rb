# frozen_string_literal: true

require "rails_helper"

# The Case timeline stays readable without becoming dishonest (HO §90).
#
# The failure being guarded against is specific. On a Case with three weeks of
# daily readings the timeline was 63 measurement lines and 3 workflow lines,
# so "what happened to this Case" — the only question the timeline exists to
# answer — could not be seen without scrolling past everything that merely
# arrived.
#
# Every remedy here is reversible by the reader: measurements are grouped by
# the event that produced them, runs fold but state their size and open in
# place, the filter is additive, and the row cap announces itself. Nothing is
# dropped, reordered, or summarised away.
RSpec.describe "Case timeline readability", type: :model do
  include TimelineHelper

  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:actor) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: actor, role: "clinical_ops") }

  let!(:source) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "BP cuff")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:detected_at) { Time.utc(2026, 3, 22, 12, 0) }

  let(:case_record) do
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new", review_priority: "today",
      started_at: detected_at - 21.days, detected_at: detected_at
    )
  end

  # One measurement event: readings taken together (STAT-004/005).
  def measure(days_ago:, values: { "health.vital.blood_pressure.systolic" => 128,
                                   "health.vital.blood_pressure.diastolic" => 70,
                                   "health.vital.pulse" => 66 },
              method: "device_automatic")
    at = detected_at - days_ago.days
    group = ObservationGroup.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, semantic_key: "health.vital.blood_pressure",
      semantic_version: 1, observed_at: at
    )

    values.each_with_index do |(key, value), index|
      Observation.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, observation_group: group,
        source_record_id: "r-#{days_ago}-#{key}",
        semantic_key: key, semantic_version: 1, value_numeric: value,
        unit: key.include?("pulse") ? "bpm" : "mmHg",
        observed_at: at + index.seconds, normalized_at: Time.current,
        quality_state: "observed", recording_method: method,
        normalizer_key: "synthetic_bp_json", normalizer_version: 1
      )
    end
    group
  end

  def timeline
    Cases::TimelineQuery.new(
      organization: organization, membership: membership, case_record: case_record
    )
  end

  describe "STAT-004/005 readings taken together are one measurement" do
    it "emits one entry per measurement event, not one per reading" do
      3.times { |index| measure(days_ago: index + 1) }

      entries = timeline.resolve.select { |entry| entry.kind == "observation" }

      expect(Observation.count).to eq(9)
      expect(entries.length).to eq(3)
    end

    it "lists the readings in the order the domain pack declares them" do
      measure(days_ago: 1)

      summary = timeline.resolve.find { |entry| entry.kind == "observation" }.summary

      # Alphabetical order would print diastolic first, which is backwards from
      # how every clinician writes a blood pressure.
      expect(summary).to eq("systolic 128.0 · diastolic 70.0 · pulse 66.0")
    end

    it "groups by instant when the source did not group its readings" do
      at = detected_at - 1.day
      %w[health.vital.blood_pressure.systolic health.vital.blood_pressure.diastolic].each do |key|
        Observation.create!(
          organization: organization, subject: subject_record, source: source,
          raw_envelope: envelope, source_record_id: "ungrouped-#{key}",
          semantic_key: key, semantic_version: 1, value_numeric: 120, unit: "mmHg",
          observed_at: at, normalized_at: Time.current, quality_state: "observed",
          recording_method: "device_automatic",
          normalizer_key: "synthetic_bp_json", normalizer_version: 1
        )
      end

      expect(timeline.resolve.count { |entry| entry.kind == "observation" }).to eq(1)
    end

    # STAT-002/010: an absent measurement is a state from the taxonomy, never
    # a zero and never a blank.
    it "names the quality state when a measurement produced no value" do
      Observation.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, source_record_id: "absent-1",
        semantic_key: "health.vital.blood_pressure.systolic", semantic_version: 1,
        observed_at: detected_at - 1.day, normalized_at: Time.current,
        quality_state: "device_not_reporting",
        normalizer_key: "synthetic_bp_json", normalizer_version: 1
      )

      entry = timeline.resolve.find { |e| e.kind == "observation" }

      expect(entry.summary).to eq("device_not_reporting")
      expect(entry.detail["missing"]).to eq("device_not_reporting")
    end
  end

  describe "the reading cap announces itself" do
    it "is not truncated for an ordinary Case" do
      3.times { |index| measure(days_ago: index + 1) }

      expect(timeline).not_to be_truncated
    end

    # A timeline that stops at the cap without saying so reads as "this is
    # everything that happened", which is the one thing a history must never
    # imply.
    it "reports truncation once the row cap is reached" do
      stub_const("Cases::TimelineQuery::OBSERVATION_ROW_LIMIT", 6)
      3.times { |index| measure(days_ago: index + 1) }

      expect(timeline).to be_truncated
    end
  end

  describe "folding runs of measurements" do
    let(:workflow_entry) do
      Cases::TimelineQuery::Entry.new(at: detected_at, kind: "case_event",
                                      summary: "Case created", detail: {}, record_id: "e1")
    end

    def reading(offset)
      Cases::TimelineQuery::Entry.new(at: detected_at - offset.days, kind: "observation",
                                      summary: "systolic 120.0", detail: {}, record_id: "o#{offset}")
    end

    it "folds a run into one item that states its own size" do
      entries = (1..6).map { |offset| reading(offset) } + [ workflow_entry ]

      folded = fold_timeline(entries, "all")
      run = folded.find { |item| item.is_a?(TimelineHelper::Run) }

      expect(folded.length).to eq(2)
      expect(run.length).to eq(6)
    end

    # Consecutive means nothing happened between them, so a fold can never
    # hide an operational entry.
    it "never folds across a non-measurement entry" do
      entries = (1..5).map { |o| reading(o) } + [ workflow_entry ] + (6..10).map { |o| reading(o) }

      folded = fold_timeline(entries, "all")

      expect(folded.count { |item| item.is_a?(TimelineHelper::Run) }).to eq(2)
      expect(folded).to include(workflow_entry)
    end

    it "leaves a short run alone rather than costing a click to save two lines" do
      entries = [ reading(1), reading(2), workflow_entry ]

      expect(fold_timeline(entries, "all")).to eq(entries)
    end

    it "does not fold when the reader asked to see readings" do
      entries = (1..6).map { |offset| reading(offset) }

      expect(fold_timeline(entries, "readings")).to eq(entries)
    end
  end

  describe "filtering" do
    let(:entries) do
      [
        Cases::TimelineQuery::Entry.new(at: detected_at, kind: "case_event", summary: "Case created", detail: {}, record_id: "e"),
        Cases::TimelineQuery::Entry.new(at: detected_at, kind: "signal", summary: "Trajectory change", detail: {}, record_id: "s"),
        Cases::TimelineQuery::Entry.new(at: detected_at, kind: "observation", summary: "systolic 120", detail: {}, record_id: "o"),
        Cases::TimelineQuery::Entry.new(at: detected_at, kind: "disposition", summary: "Action taken", detail: {}, record_id: "d")
      ]
    end

    it "counts every filter against the same entry set" do
      counts = timeline_counts(entries)

      expect(counts["all"]).to eq(4)
      expect(counts["workflow"]).to eq(2)
      expect(counts["signals"]).to eq(1)
      expect(counts["readings"]).to eq(1)
    end

    it "keeps workflow entries together regardless of which table they came from" do
      kinds = filter_timeline(entries, "workflow").map(&:kind)

      expect(kinds).to contain_exactly("case_event", "disposition")
    end

    it "falls back to everything for an unknown filter rather than showing nothing" do
      expect(timeline_filter("bogus")).to eq("all")
      expect(filter_timeline(entries, timeline_filter(nil)).length).to eq(4)
    end
  end
end
