# frozen_string_literal: true

require "rails_helper"

# Materializing baselines (epic 003-07/003-08; HO §26, §57, §99; SC §19–22;
# INV-3, INV-13/14).
#
# `PersonalRecent` has been able to build a baseline since 003-08 and nothing
# persisted one. These specs cover the persistence: that it is idempotent on
# artifact identity, that it is immutable once written, that it records what
# it rested on, and that late data produces a new artifact rather than
# rewriting an old one.
RSpec.describe "Baseline materialization", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
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

  let(:key) { "health.vital.blood_pressure.systolic" }
  let(:as_of) { Time.utc(2026, 3, 22, 0, 0) }

  def observe(days_ago:, value: 120, subject: subject_record, minute: 0)
    Observation.create!(
      organization: organization, subject: subject, source: source, raw_envelope: envelope,
      source_record_id: "r-#{subject.id}-#{days_ago}-#{minute}",
      semantic_key: key, semantic_version: 1, value_numeric: value, unit: "mmHg",
      observed_at: as_of - days_ago.days + 12.hours + minute.minutes,
      normalized_at: Time.current, quality_state: "observed",
      recording_method: "device_automatic",
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def materialize(subject: subject_record, at: as_of)
    Baselines::Materialize.call(subject: subject, semantic_key: key, as_of: at)
  end

  describe "HO §26 identity" do
    before { 14.times { |i| observe(days_ago: i + 1, value: 118 + i) } }

    it "creates the artifact once" do
      outcome = materialize

      expect(outcome).to be_created
      expect(Analysis::BaselineInstance.count).to eq(1)
    end

    # What makes the coordinator's per-stage retry safe (HO §98).
    it "returns the existing artifact rather than a second one" do
      first = materialize
      second = materialize

      expect(second).not_to be_created
      expect(second.baseline.id).to eq(first.baseline.id)
      expect(Analysis::BaselineInstance.count).to eq(1)
    end

    # HO §99, STAT-040/041: late data does not rewrite a baseline. It produces
    # a new one, and whatever points at baselines moves its pointer.
    it "produces a new artifact when the inputs change, leaving the old one alone" do
      first = materialize
      observe(days_ago: 0, value: 190)
      second = materialize(at: as_of + 1.hour)

      expect(second).to be_created
      expect(second.baseline.id).not_to eq(first.baseline.id)
      expect { first.baseline.reload }.not_to raise_error
    end

    # INV-13/14. Analytical artifacts are immutable snapshots.
    it "refuses to be updated after it is written" do
      baseline = materialize.baseline

      expect(baseline).to be_readonly
      expect { baseline.update!(maturity: "mature") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "SC §21 what a baseline stores" do
    it "records usable units, span, maturity — and which measure it is of" do
      14.times { |i| observe(days_ago: i + 1, value: 118 + i) }

      baseline = materialize.baseline

      expect(baseline.semantic_key).to eq(key)
      expect(baseline.semantic_version).to eq(1)
      expect(baseline.usable_units).to eq(14)
      expect(baseline.calendar_span_days).to eq(14)
      expect(baseline.maturity).to eq("partial")
    end

    # SC §29's robust standardized effect has nothing to compute from without
    # a centre AND a scale, which is why the migration added both.
    it "records the centre and the scale" do
      14.times { |i| observe(days_ago: i + 1, value: 120 + i) }

      baseline = materialize.baseline

      expect(baseline.central_value.to_f).to be_within(0.01).of(126.5)
      expect(baseline.dispersion).to be_present
      expect(baseline.unit).to eq("mmHg")
    end

    # STAT-002 forbids inventing a stand-in, and SC §22's aggregation needs
    # three days before a scale exists at all.
    it "leaves dispersion null rather than fabricating one from two days" do
      2.times { |i| observe(days_ago: i + 1) }

      baseline = materialize.baseline

      expect(baseline.dispersion).to be_nil
      expect(baseline.maturity).to eq("immature")
    end

    # INV-3: a baseline must never exist without the record of what produced
    # it, which is what makes a Finding built on it drill down to source rows.
    it "records the exact rows it rested on" do
      14.times { |i| observe(days_ago: i + 1) }

      baseline = materialize.baseline

      expect(baseline.evidence_set).to be_present
      expect(baseline.inputs.length).to eq(14)
      expect(baseline.inputs.first).to be_a(Observation)
    end

    # HO §80: a threshold change is visible in the artifact itself, not only
    # in git history.
    it "pins the versions it was computed under" do
      14.times { |i| observe(days_ago: i + 1) }

      tuple = materialize.baseline.version_tuple

      expect(tuple.dig("definition", "key")).to eq("personal_recent")
      expect(tuple.dig("definition", "digest")).to be_present
      expect(tuple["statistical_config_digest"]).to be_present
    end
  end

  # SC §66: "Default cohort analysis unit: subject… Subject-level features are
  # computed first." Computed first is why this is a batch and not a read.
  describe "cohort materialization" do
    let!(:peer) { Subject.create!(organization: organization, timezone: "UTC") }
    let!(:unenrolled) { Subject.create!(organization: organization, timezone: "UTC") }

    before do
      14.times { |i| observe(days_ago: i + 1, value: 118 + i) }
      14.times { |i| observe(days_ago: i + 1, value: 130 + i, subject: peer, minute: 1) }
    end

    it "materializes one baseline per subject with data" do
      outcome = Baselines::MaterializeCohort.call(
        organization: organization, semantic_key: key, as_of: as_of
      )

      expect(outcome.created).to eq(2)
      expect(Analysis::BaselineInstance.pluck(:subject_id)).to contain_exactly(subject_record.id, peer.id)
    end

    # A baseline over nothing is immature by definition, and rows for subjects
    # who never enrolled in the measure would dilute every cohort denominator
    # computed from the table.
    it "skips subjects with no readings for the measure" do
      Baselines::MaterializeCohort.call(organization: organization, semantic_key: key, as_of: as_of)

      expect(Analysis::BaselineInstance.where(subject_id: unenrolled.id)).to be_empty
    end

    it "is safe to run again" do
      Baselines::MaterializeCohort.call(organization: organization, semantic_key: key, as_of: as_of)
      second = Baselines::MaterializeCohort.call(organization: organization, semantic_key: key, as_of: as_of)

      expect(second.created).to eq(0)
      expect(second.existing).to eq(2)
      expect(Analysis::BaselineInstance.count).to eq(2)
    end

    # INV-31, on a batch that reads across every subject in an organization.
    it "never reaches into another organization" do
      other_org = create_organization(name: "Southside", slug: "southside")
      other_subject = Subject.create!(organization: other_org, timezone: "UTC")

      Baselines::MaterializeCohort.call(organization: organization, semantic_key: key, as_of: as_of)

      expect(Analysis::BaselineInstance.where(subject_id: other_subject.id)).to be_empty
      expect(Analysis::BaselineInstance.distinct.pluck(:organization_id)).to eq([ organization.id ])
    end
  end

  describe "the job" do
    before { 14.times { |i| observe(days_ago: i + 1) } }

    # CLAUDE.md: pass IDs to jobs, never payloads.
    it "takes identifiers and no health data" do
      arguments = { organization_id: organization.id, semantic_key: key, as_of: as_of.iso8601 }

      expect(arguments.values.map(&:class)).to all(satisfy { |c| [ String ].include?(c) })
      expect(arguments.to_json).not_to include("118", "120")
    end

    it "materializes through the same idempotent path" do
      Analysis::BaselineMaterializationJob.perform_now(
        organization_id: organization.id, semantic_key: key, as_of: as_of.iso8601
      )
      Analysis::BaselineMaterializationJob.perform_now(
        organization_id: organization.id, semantic_key: key, as_of: as_of.iso8601
      )

      expect(Analysis::BaselineInstance.count).to eq(1)
    end
  end
end
