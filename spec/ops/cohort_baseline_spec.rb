# frozen_string_literal: true

require "rails_helper"

# Where a subject sits among the program's baselines (002x-01/02; SC §25, §64,
# §66; STAT-021).
#
# The defect this closes: the cohort prior pooled RAW READINGS across subjects,
# so a subject measuring four times a day carried four times the weight of one
# measuring daily. SC §66 names the unit — subject, not observation — and the
# reason: "This prevents patients with dense telemetry from dominating the
# sample."
RSpec.describe "Cohort baseline comparison", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_organization) { create_organization(name: "Southside", slug: "southside") }
  let!(:focus) { Subject.create!(organization: organization, timezone: "UTC") }
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

  def observe(subject:, days_ago:, value:, minute: 0, org: organization, src: source, env: envelope)
    Observation.create!(
      organization: org, subject: subject, source: src, raw_envelope: env,
      source_record_id: "r-#{subject.id}-#{days_ago}-#{minute}",
      semantic_key: key, semantic_version: 1, value_numeric: value, unit: "mmHg",
      observed_at: as_of - days_ago.days + 12.hours + minute.minutes,
      normalized_at: Time.current, quality_state: "observed",
      recording_method: "device_automatic",
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  # A peer with a flat record at `level`, dense enough to be a partial
  # baseline. Each peer gets its own envelope: the normalization identity is
  # (envelope, key, version, observed_at), so two subjects measured at the same
  # instant from one envelope is a duplicate, not two measurements.
  def peer_at(level, readings_per_day: 1)
    peer = Subject.create!(organization: organization, timezone: "UTC")
    peer_envelope = RawEnvelope.create!(
      organization: organization, source: source, source_record_id: "env-#{peer.id}",
      content_type: "application/json", object_key: "k-#{peer.id}", content_hash: "h-#{peer.id}",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )

    14.times do |day|
      readings_per_day.times do |n|
        observe(subject: peer, days_ago: day + 1, value: level, minute: n, env: peer_envelope)
      end
    end
    peer
  end

  def query(exclude: focus)
    Ops::CohortBaselineQuery.new(
      organization: organization, semantic_key: key, exclude_subject: exclude
    )
  end

  def materialize_all
    Baselines::MaterializeCohort.call(organization: organization, semantic_key: key, as_of: as_of)
  end

  describe "SC §66 the analysis unit is the subject" do
    # The defect, stated as a test: one subject with dense telemetry must not
    # move the cohort more than one subject with sparse telemetry.
    it "weights a dense-telemetry subject exactly like a sparse one" do
      peer_at(120, readings_per_day: 1)
      peer_at(120, readings_per_day: 1)
      peer_at(180, readings_per_day: 8)
      materialize_all

      distribution = query.distribution

      expect(distribution.subject_count).to eq(3)
      # Pooled by reading the median would sit near 180, because that subject
      # contributed eight times the rows.
      expect(distribution.median).to eq(120.0)
    end

    it "counts one baseline per subject, not one per snapshot" do
      peer_at(120)
      materialize_all
      # A later run at a new as_of is a new immutable artifact, not an update.
      Baselines::MaterializeCohort.call(
        organization: organization, semantic_key: key, as_of: as_of + 1.day
      )

      expect(Analysis::BaselineInstance.count).to be > 1
      expect(query.distribution.subject_count).to eq(1)
    end

    it "uses each subject's most recent baseline" do
      peer = peer_at(120)
      materialize_all
      observe(subject: peer, days_ago: 0, value: 200, minute: 5)
      Baselines::MaterializeCohort.call(
        organization: organization, semantic_key: key, as_of: as_of + 1.day
      )

      latest = Analysis::BaselineInstance.where(subject: peer).order(:as_of).last

      expect(query.distribution.median).to eq(latest.central_value.to_f)
    end
  end

  describe "the distribution" do
    before do
      [ 110, 118, 122, 130, 150 ].each { |level| peer_at(level) }
      materialize_all
    end

    it "reports the spread rather than a single number" do
      distribution = query.distribution

      expect(distribution.min).to eq(110.0)
      expect(distribution.max).to eq(150.0)
      expect(distribution.median).to eq(122.0)
      expect(distribution.p25).to be <= distribution.median
      expect(distribution.p75).to be >= distribution.median
    end

    # A percentile and an inside/outside flag rather than a z-score, which
    # would imply a shape nobody has checked.
    it "places a value in the distribution without assuming a shape" do
      position = query.position_of(150.0)

      expect(position.percentile).to eq(80)
      expect(position.inside_iqr).to be(false)
      expect(query.position_of(122.0).inside_iqr).to be(true)
    end

    it "excludes the subject under examination from their own comparison" do
      focus_peer = peer_at(300)
      materialize_all

      expect(query(exclude: focus_peer).distribution.max).to eq(150.0)
      expect(query(exclude: nil).distribution.max).to eq(300.0)
    end

    # A cohort that silently shrank makes every share computed from it wrong
    # by an unknown amount.
    it "states how many subjects have a baseline out of how many have data" do
      Subject.create!(organization: organization, timezone: "UTC").tap do |straggler|
        observe(subject: straggler, days_ago: 1, value: 125, minute: 3)
      end

      distribution = query.distribution

      expect(distribution.subjects_with_data).to eq(6)
      expect(distribution.subject_count).to eq(5)
      expect(distribution.coverage).to be < 1.0
    end

    it "reports the maturity mix, because a spread of noise looks like a spread" do
      expect(query.distribution.maturity_counts).to eq("partial" => 5)
    end

    it "carries the as_of it was computed at" do
      expect(query.distribution.as_of).to eq(as_of)
    end
  end

  # SC §25: 20 affected and 20 baseline subjects for provider-facing Difference
  # RANKING. This surface ranks nothing, so descriptive aggregate display
  # applies — but the reader is told which side of the line they are on.
  describe "SC §25 cohort minimums" do
    it "flags a cohort below the ranking floor" do
      3.times { |i| peer_at(120 + i) }
      materialize_all

      expect(query.distribution).to be_below_ranking_minimum
    end

    it "does not flag a cohort above it" do
      Ops::CohortBaselineQuery::RANKING_MINIMUM_SUBJECTS.times { |i| peer_at(115 + i) }
      materialize_all

      expect(query.distribution).not_to be_below_ranking_minimum
    end
  end

  # INV-31, on a query whose whole purpose is to read across every subject.
  it "never reads another organization's baselines" do
    peer_at(120)
    materialize_all

    foreign = Subject.create!(organization: other_organization, timezone: "UTC")
    foreign_source = Source.create!(organization: other_organization, key: "cuff",
                                    source_type: "device_cloud", display_name: "BP cuff")
    foreign_envelope = RawEnvelope.create!(
      organization: other_organization, source: foreign_source, source_record_id: "r9",
      content_type: "application/json", object_key: "k9", content_hash: "h9",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
    14.times do |day|
      observe(subject: foreign, days_ago: day + 1, value: 300,
              org: other_organization, src: foreign_source, env: foreign_envelope)
    end
    Baselines::MaterializeCohort.call(
      organization: other_organization, semantic_key: key, as_of: as_of
    )

    expect(query.distribution.subject_count).to eq(1)
    expect(query.distribution.max).to eq(120.0)
  end

  it "reports nothing rather than guessing when no baseline has been materialized" do
    peer_at(120)

    expect(query.distribution).not_to be_any
    expect(query.position_of(130.0)).to be_nil
  end
end
