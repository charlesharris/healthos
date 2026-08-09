# frozen_string_literal: true

require "rails_helper"

# Epic 002-21 Ops Queue v1. HO §84–87; S2C-011, S2C-013, S2C-019; INV-31/32.
RSpec.describe "Ops Queue", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_org) { create_organization(name: "Southside", slug: "southside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:operator) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: operator, role: "clinical_ops") }
  let!(:colleague) { create_user(email: "colleague@example.test") }
  let!(:colleague_membership) { create_membership(organization: organization, user: colleague, role: "clinician") }
  let!(:team) { Team.create!(organization: organization, name: "clinical") }

  let(:now) { Time.utc(2026, 3, 22, 12, 0) }

  def build_case(organization: self.organization, subject: subject_record, **attrs)
    Cases::CaseRecord.create!(
      organization: organization, subject: subject,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      started_at: now - 7.days, detected_at: now, **attrs
    )
  end

  before { sign_in operator }

  describe "tabs and counts (HO §87)" do
    it "shows a count per status and defaults to active work" do
      build_case(status: "new", title: "New work")
      build_case(status: "investigating", title: "In progress")
      build_case(status: "resolved", title: "Old news", resolved_at: now)

      get ops_cases_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Active (2)")
      expect(response.body).to include("Resolved (1)")
      expect(response.body).to include("New work", "In progress")
      expect(response.body).not_to include("Old news")
    end

    it "shows closed work only when the tab asks for it" do
      build_case(status: "resolved", title: "Old news", resolved_at: now)

      get ops_cases_path(status: "resolved")

      expect(response.body).to include("Old news")
    end

    it "falls back to the active tab for an unknown status rather than filtering on junk" do
      build_case(title: "New work")

      get ops_cases_path(status: "not_a_status")

      expect(response.body).to include("New work")
    end
  end

  describe "filters and sort (HO §85)" do
    it "filters by priority, owner and team" do
      build_case(title: "Urgent one", review_priority: "now")
      build_case(title: "Mine", owner: operator)
      build_case(title: "Team work", team: team)

      get ops_cases_path(priority: "now")
      expect(response.body).to include("Urgent one")
      expect(response.body).not_to include("Team work")

      get ops_cases_path(owner: "me")
      expect(response.body).to include("Mine")
      expect(response.body).not_to include("Urgent one")

      get ops_cases_path(team: team.id)
      expect(response.body).to include("Team work")
      expect(response.body).not_to include("Mine")
    end

    it "filters to unclaimed work" do
      build_case(title: "Claimed", owner: operator)
      build_case(title: "Unclaimed")

      get ops_cases_path(owner: Ops::CaseQuery::UNASSIGNED)

      expect(response.body).to include("Unclaimed")
      expect(response.body).not_to include(">Claimed<")
    end

    # S2C-023: the page states the order in words. A queue whose order cannot
    # be explained is a queue nobody can argue with.
    it "states its ordering on the page" do
      build_case

      get ops_cases_path

      expect(response.body).to include("Review priority (now")
    end

    it "orders urgent work above routine work" do
      build_case(title: "Routine item", review_priority: "routine")
      build_case(title: "Urgent item", review_priority: "now")

      get ops_cases_path

      expect(response.body.index("Urgent item")).to be < response.body.index("Routine item")
    end
  end

  describe "pagination (HO §86)" do
    it "pages the list and links to the next page" do
      3.times { |i| build_case(title: "Case #{i}", detected_at: now - i.days) }

      get ops_cases_path(per_page: 2)

      expect(response.body).to include("Page 1 of 2")
      expect(response.body).to include("Next")
    end
  end

  describe "assignment (HO §87, S2C-013)" do
    it "assigns an owner through the service, with timeline and audit" do
      case_record = build_case

      expect {
        patch ops_case_assignment_path(case_record), params: { assignment: { owner_id: colleague.id } }
      }.to change(AuditEvent.where(event_type: "case.assigned"), :count).by(1)

      expect(case_record.reload.owner).to eq(colleague)
      expect(case_record.case_events.where(event_type: "assigned").last.payload["assigned_by"]).to eq("user")
      expect(response).to have_http_status(:see_other)
    end

    it "unassigns when the form submits an empty owner" do
      case_record = build_case(owner: colleague)

      patch ops_case_assignment_path(case_record), params: { assignment: { owner_id: "" } }

      expect(case_record.reload.owner).to be_nil
    end

    it "refreshes just the row for a Turbo submission (HO §87 live row refresh)" do
      case_record = build_case

      patch ops_case_assignment_path(case_record),
            params: { row: "1", assignment: { owner_id: colleague.id } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include(case_record.subject.public_id)
    end

    # An owner who cannot open the Case is not an owner. support_limited is
    # deliberately excluded from clinical access (HO §157).
    it "refuses to assign to a membership without clinical access" do
      support = create_user(email: "support@example.test")
      create_membership(organization: organization, user: support, role: "support_limited")
      case_record = build_case

      patch ops_case_assignment_path(case_record), params: { assignment: { owner_id: support.id } }

      expect(case_record.reload.owner).to be_nil
      expect(flash[:alert]).to be_present
    end

    it "refuses an owner from another organization" do
      outsider = create_user(email: "outsider@example.test")
      create_membership(organization: other_org, user: outsider, role: "clinician")
      case_record = build_case

      patch ops_case_assignment_path(case_record), params: { assignment: { owner_id: outsider.id } }

      expect(case_record.reload.owner).to be_nil
    end
  end

  describe "triage from the queue (S2C-013)" do
    it "moves state through Cases::Transition, leaving a timeline entry" do
      case_record = build_case

      patch ops_case_state_path(case_record), params: { state: { to: "triaged" } }

      expect(case_record.reload.status).to eq("triaged")
      expect(case_record.case_events.pluck(:event_type)).to include("triaged")
      expect(case_record.last_reviewed_at).to be_present
    end
  end

  describe "HO §84 subject identity is secondary and opaque" do
    it "renders the public handle and no identifying value" do
      SubjectIdentity.create!(
        subject: subject_record, first_name: "Zephyrine", last_name: "Quattlebaum",
        date_of_birth: "1962-04-11", contact_email: "zq@example.test", contact_phone: "+15551234567"
      )
      SubjectIdentifier.create!(
        organization: organization, subject: subject_record, system: "mrn", value: "MRN-ZQ-99881"
      )
      build_case

      get ops_cases_path

      expect(response.body).to include(subject_record.public_id)
      [ "Zephyrine", "Quattlebaum", "1962-04-11", "zq@example.test", "+15551234567", "MRN-ZQ-99881" ]
        .each { |value| expect(response.body).not_to include(value) }
    end
  end

  describe "S2C-019 analysis never hides a Case" do
    it "shows failed and insufficient_evidence as different, still-actionable states" do
      build_case(title: "Analysis broke", analysis_status: "failed")
      build_case(title: "Not enough data", analysis_status: "insufficient_evidence")

      get ops_cases_path

      expect(response.body).to include("Analysis broke", "Not enough data")
      expect(response.body).to include("Failed")
      expect(response.body).to include("Insufficient evidence")
    end
  end

  describe "INV-31 tenancy" do
    it "never shows another organization's work" do
      other_subject = Subject.create!(organization: other_org, timezone: "UTC")
      build_case(organization: other_org, subject: other_subject, title: "Southside work")
      build_case(title: "Northside work")

      get ops_cases_path

      expect(response.body).to include("Northside work")
      expect(response.body).not_to include("Southside work")
    end

    it "404s on a Case id from another organization rather than confirming it exists" do
      other_subject = Subject.create!(organization: other_org, timezone: "UTC")
      foreign = build_case(organization: other_org, subject: other_subject)

      get ops_case_path(foreign)
      expect(response).to have_http_status(:not_found)

      patch ops_case_state_path(foreign), params: { state: { to: "triaged" } }
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.status).to eq("new")
    end

    it "requires authentication" do
      delete session_path
      get ops_cases_path

      expect(response).to redirect_to(new_session_path)
    end
  end
end
