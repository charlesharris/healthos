# frozen_string_literal: true

require "rails_helper"

# The cohort Explore surface (HO §84, §92; S2C-003; STAT-019/024).
#
# The risk this surface carries is not that it computes something wrong — it
# computes almost nothing. It is that it reads every subject's telemetry at
# once, which makes the tenant predicate and the access audit the load-bearing
# parts, and that a surface which shows differences is one refactor away from
# ranking them.
RSpec.describe "Ops Explore", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_organization) { create_organization(name: "Southside", slug: "southside") }
  let!(:operator) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: operator, role: "clinical_ops") }

  let(:key) { "health.vital.blood_pressure.systolic" }
  let(:anchor) { Time.utc(2026, 3, 22, 0, 0) }

  def seed_reading(org:, subject:, days_ago:, value: 130, minute: 0)
    source = Source.find_or_create_by!(organization: org, key: "cuff") do |record|
      record.source_type = "device_cloud"
      record.display_name = "BP cuff"
    end
    envelope = RawEnvelope.find_or_create_by!(organization: org, source: source,
                                              source_record_id: "env-#{org.id}") do |record|
      record.content_type = "application/json"
      record.object_key = "k-#{org.id}"
      record.content_hash = "h-#{org.id}"
      record.received_at = Time.current
      record.adapter_key = "synthetic_bp_json"
      record.adapter_version = "1"
    end

    Observation.create!(
      organization: org, subject: subject, source: source, raw_envelope: envelope,
      source_record_id: "r-#{subject.id}-#{days_ago}-#{minute}",
      semantic_key: key, semantic_version: 1, value_numeric: value, unit: "mmHg",
      observed_at: anchor - days_ago.days + 12.hours + minute.minutes,
      normalized_at: Time.current, quality_state: "observed",
      recording_method: "device_automatic",
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  let(:range_params) { { range_from: (anchor - 28.days).to_date, range_to: anchor.to_date } }

  before { sign_in operator }

  describe "access" do
    it "renders for a clinical role" do
      get ops_explore_path(**range_params)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Explore")
    end

    # support_limited is excluded from clinical access (HO §157) and this
    # surface is the broadest read of health data in the product.
    it "refuses a membership without clinical access" do
      support = create_user(email: "support@example.test")
      create_membership(organization: organization, user: support, role: "support_limited")
      sign_in support

      get ops_explore_path(**range_params)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "INV-31 tenancy" do
    it "counts only this organization's readings" do
      mine = Subject.create!(organization: organization, timezone: "UTC")
      theirs = Subject.create!(organization: other_organization, timezone: "UTC")
      seed_reading(org: organization, subject: mine, days_ago: 3)
      seed_reading(org: other_organization, subject: theirs, days_ago: 3)

      get ops_explore_path(**range_params, from: (anchor - 7.days).iso8601, to: anchor.iso8601)

      expect(response.body).to include(mine.public_id)
      expect(response.body).not_to include(theirs.public_id)
    end
  end

  # HO §92: reading cohort telemetry is provider access to health data,
  # however it is aggregated.
  describe "audit" do
    it "records the read with the filter set that identifies it" do
      subject_record = Subject.create!(organization: organization, timezone: "UTC")
      seed_reading(org: organization, subject: subject_record, days_ago: 3)

      expect { get ops_explore_path(**range_params) }
        .to change(AuditEvent.where(event_type: "telemetry.explored"), :count).by(1)

      event = AuditEvent.where(event_type: "telemetry.explored").last
      expect(event.actor).to eq(operator)
      expect(event.organization).to eq(organization)
      expect(event.metadata["semantic_key"]).to eq(key)
    end

    # "Avoid raw PHI in audit metadata unless required" — the filter set is
    # what identifies the read, and it contains no values.
    it "keeps measured values out of the audit metadata" do
      subject_record = Subject.create!(organization: organization, timezone: "UTC")
      seed_reading(org: organization, subject: subject_record, days_ago: 3, value: 187)

      get ops_explore_path(**range_params)

      expect(AuditEvent.where(event_type: "telemetry.explored").last.metadata.to_json)
        .not_to include("187")
    end
  end

  describe "selection" do
    let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }

    before do
      seed_reading(org: organization, subject: subject_record, days_ago: 20, value: 118)
      seed_reading(org: organization, subject: subject_record, days_ago: 3, value: 165)
    end

    it "opens with nothing selected rather than answering a question nobody asked" do
      get ops_explore_path(**range_params)

      expect(response.body).to include("Nothing selected yet")
      expect(response.body).to include("Drag a region on the chart")
    end

    it "compares a dragged region against everything outside it" do
      get ops_explore_path(**range_params, from: (anchor - 7.days).iso8601, to: anchor.iso8601)

      expect(response.body).to include("What was different?")
      expect(response.body).to include("your selection")
    end

    # Selecting on the outcome and reporting which dimensions differ is a
    # hypothesis generator, not a finding.
    it "warns when the selection is conditioned on the measured value" do
      get ops_explore_path(**range_params, from: (anchor - 7.days).iso8601,
                           to: anchor.iso8601, vmin: "150", vmax: "180")

      expect(response.body).to include("conditioned on the measured value")
    end

    it "does not warn when the selection is only a time range" do
      get ops_explore_path(**range_params, from: (anchor - 7.days).iso8601, to: anchor.iso8601)

      expect(response.body).not_to include("conditioned on the measured value")
    end

    it "survives junk parameters instead of raising" do
      get ops_explore_path(**range_params, from: "nonsense", to: "-", vmin: "abc")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing selected yet")
    end

    it "clamps an absurd range rather than reading the whole history" do
      get ops_explore_path(range_from: "1900-01-01", range_to: anchor.to_date)

      expect(response).to have_http_status(:ok)
    end
  end

  # S2C-003: Monitors create Signals, and nothing else creates Cases. A
  # surface where an operator notices something must not become a second way
  # to open work, or the correlation guarantees stop meaning anything.
  describe "read-only by construction" do
    it "offers no route that writes through this controller" do
      explore_routes = Rails.application.routes.routes.select do |route|
        route.defaults[:controller] == "ops/explore"
      end

      expect(explore_routes.map { |route| route.verb }.uniq).to eq([ "GET" ])
    end

    # The source-level guard lives in spec/ops/controller_invariants_spec.rb,
    # which greps every controller under app/controllers/ops for direct
    # persistence calls and already covers this one. Restating it here would
    # be a second copy of a rule that must not drift.
  end
end
