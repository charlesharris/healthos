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

  describe "drilling into a dimension" do
    let!(:mine) { Subject.create!(organization: organization, timezone: "UTC") }
    let!(:other) { Subject.create!(organization: organization, timezone: "UTC") }

    before do
      seed_reading(org: organization, subject: mine, days_ago: 3, value: 165)
      seed_reading(org: organization, subject: other, days_ago: 3, value: 118, minute: 1)
    end

    it "shows the active scope so the counts below can be read correctly" do
      get ops_explore_path(**range_params, where: { subject: mine.public_id })

      expect(response.body).to include("Scoped to")
      expect(response.body).to include("Every count below is within this scope")
    end

    # The handle has to survive verbatim: an operator compares it against a
    # queue row and copies it. Humanizing enum values corrupts identifiers.
    it "keeps an opaque handle intact in the scope chip" do
      get ops_explore_path(**range_params, where: { subject: mine.public_id })

      expect(response.body).to include(mine.public_id)
      expect(response.body).not_to include(mine.public_id.tr("_", " "))
    end

    it "still humanizes an enum filter value" do
      get ops_explore_path(**range_params, where: { recording_method: "device_automatic" })

      expect(response.body).to include("device automatic")
    end

    # Drilling all the way to one subject turns the cohort view into theirs.
    it "plots the subject's own readings once scoped to them" do
      get ops_explore_path(**range_params, where: { subject: mine.public_id })

      expect(response.body).to include("subject · baseline")
    end

    # A stale link should show the cohort, not an error page.
    it "ignores an unknown handle rather than failing" do
      get ops_explore_path(**range_params, where: { subject: "sub_nope" })

      expect(response).to have_http_status(:ok)
    end

    # INV-31 again, on the drill-down path this time.
    it "does not resolve a handle from another organization" do
      theirs = Subject.create!(organization: other_organization, timezone: "UTC")

      get ops_explore_path(**range_params, where: { subject: theirs.public_id })

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("subject · baseline")
    end

    it "ignores a dimension that is not on the whitelist" do
      get ops_explore_path(**range_params, where: { organization_id: "x" })

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Scoped to")
    end
  end

  # Honeycomb puts every event on one heatmap because everything it plots is
  # duration_ms. mmHg and bpm on one axis would be the dual-axis chart, which
  # invents a correlation from an arbitrary alignment of two scales. Small
  # multiples are the honest equivalent — and they only mean anything if the
  # panels share their scales.
  describe "small multiples" do
    let!(:mine) { Subject.create!(organization: organization, timezone: "UTC") }

    before do
      seed_reading(org: organization, subject: mine, days_ago: 3, value: 165)
      seed_reading(org: organization, subject: mine, days_ago: 4, value: 118, minute: 1)
    end

    it "renders one chart when nothing is split" do
      get ops_explore_path(**range_params)

      expect(response.body).not_to include("panel-title")
    end

    it "splits by measure without forcing different units onto one axis" do
      %w[health.vital.blood_pressure.diastolic health.vital.pulse].each_with_index do |other, index|
        Observation.create!(
          organization: organization, subject: mine,
          source: Source.find_by(organization: organization, key: "cuff"),
          raw_envelope: RawEnvelope.find_by(organization: organization),
          source_record_id: "extra-#{index}", semantic_key: other, semantic_version: 1,
          value_numeric: 70 + index, unit: other.include?("pulse") ? "bpm" : "mmHg",
          observed_at: anchor - 3.days + 13.hours, normalized_at: Time.current,
          quality_state: "observed", recording_method: "device_automatic",
          normalizer_key: "synthetic_bp_json", normalizer_version: 1
        )
      end

      get ops_explore_path(**range_params, split: "measure")

      expect(response.body.scan(/class="panel-title/).length).to eq(3)
    end

    it "falls back to one chart when a dimension has only one value" do
      get ops_explore_path(**range_params, split: "recording_method")

      expect(response.body).not_to include("panel-title")
    end

    it "ignores an unknown split rather than failing" do
      get ops_explore_path(**range_params, split: "nonsense")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("panel-title")
    end
  end

  # Explore notices things; only a Monitor opens a Case (S2C-003), so the way
  # out of here is into work that already exists.
  describe "drilling through to existing work" do
    let!(:mine) { Subject.create!(organization: organization, timezone: "UTC") }

    before { seed_reading(org: organization, subject: mine, days_ago: 3) }

    it "lists the scoped subject's Cases" do
      case_record = Cases::CaseRecord.create!(
        organization: organization, subject: mine, domain_key: "hypertension",
        case_type: "blood_pressure_change", title: "Blood pressure pattern change",
        status: "new", review_priority: "today",
        started_at: anchor - 7.days, detected_at: anchor
      )

      get ops_explore_path(**range_params, where: { subject: mine.public_id })

      expect(response.body).to include("Cases for this subject")
      expect(response.body).to include(ops_case_path(case_record))
    end

    it "says so plainly when the subject has no Case, rather than offering to make one" do
      get ops_explore_path(**range_params, where: { subject: mine.public_id })

      expect(response.body).to include("No Case has been raised for this subject")
      expect(response.body).to include("never from here")
    end

    # INV-31 on the Case listing too, not just the telemetry.
    it "never lists a Case from another organization" do
      theirs = Subject.create!(organization: other_organization, timezone: "UTC")
      Cases::CaseRecord.create!(
        organization: other_organization, subject: theirs, domain_key: "hypertension",
        case_type: "blood_pressure_change", title: "Not yours", status: "new",
        review_priority: "today", started_at: anchor - 7.days, detected_at: anchor
      )

      get ops_explore_path(**range_params, where: { subject: theirs.public_id })

      expect(response.body).not_to include("Not yours")
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
