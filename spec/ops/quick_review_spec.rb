# frozen_string_literal: true

require "rails_helper"

# Epic 002-22 Quick Review. HO §88, §90, §92; S2C-011, S2C-013, S2C-015,
# S2C-016, S2C-019.
RSpec.describe "Quick Review", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:operator) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: operator, role: "clinical_ops") }
  let!(:team) { Team.create!(organization: organization, name: "clinical") }

  let(:now) { Time.utc(2026, 3, 22, 12, 0) }

  let(:case_record) do
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      review_priority: "today",
      priority_reasons: [ { "code" => "aged_unreviewed", "explanation" => "Open and never reviewed" } ],
      started_at: now - 7.days, detected_at: now
    )
  end

  def attach_signal(relationship: "trigger", signal_type: "trajectory_change", **attrs)
    signal = Monitoring::Signal.create!(
      organization: organization, subject: subject_record,
      monitor_key: "blood_pressure_trajectory_change", monitor_version: 1,
      monitor_digest: "abc123def456", signal_type: signal_type, domain_key: "hypertension",
      detected_at: now, window_started_at: now - 14.days, window_ended_at: now,
      severity: "moderate", attributes_json: { "direction" => "increase", "delta" => 18 },
      deduplication_key: SecureRandom.hex(16), **attrs
    )
    Cases::CaseSignal.create!(
      organization: organization, case_record: case_record, signal: signal,
      relationship: relationship, attached_at: now,
      explanation: { "explanation" => "Same subject, same domain, overlapping window" }
    )
    signal
  end

  before { sign_in operator }

  describe "why is this here (HO §88)" do
    it "shows the trigger Signal, its monitor and its attributes" do
      attach_signal

      get ops_case_path(case_record)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Why is this here?")
      expect(response.body).to include("Trajectory change")
      expect(response.body).to include("blood_pressure_trajectory_change@v1")
      expect(response.body).to include("Direction", "increase")
    end

    it "shows contextual attachments with the correlation explanation (§158)" do
      attach_signal(relationship: "contextual", signal_type: "source_change")

      get ops_case_path(case_record)

      expect(response.body).to include("contextual")
      expect(response.body).to include("Same subject, same domain, overlapping window")
    end

    it "says so plainly when no Signal is attached rather than rendering an empty block" do
      get ops_case_path(case_record)

      expect(response.body).to include("No trigger Signal is attached")
    end

    # S2C-011/012: priority is operational policy, and it is never unexplained.
    it "shows review priority with its reasons and no numeric score" do
      get ops_case_path(case_record)

      expect(response.body).to include("today")
      expect(response.body).to include("aged_unreviewed")
      expect(response.body).not_to match(/risk score|priority score|score:/i)
    end
  end

  describe "timeline (HO §90)" do
    it "renders the merged timeline" do
      attach_signal
      Cases::CaseEvent.append!(case_record: case_record, event_type: "case_created")

      get ops_case_path(case_record)

      expect(response.body).to include("Case created")
      expect(response.body).to include("Signal")
    end
  end

  describe "viewing is audited, not timelined (HO §92)" do
    it "writes an AuditEvent" do
      expect { get ops_case_path(case_record) }
        .to change(AuditEvent.where(event_type: "case.viewed"), :count).by(1)

      event = AuditEvent.where(event_type: "case.viewed").last
      expect(event.actor).to eq(operator)
      expect(event.metadata["case_id"]).to eq(case_record.id)
    end

    # A timeline full of "Dr X looked at this" would drown the workflow
    # history and leak who is reviewing whom to everyone with queue access.
    it "writes no CaseEvent" do
      case_record

      expect { get ops_case_path(case_record) }.not_to change(Cases::CaseEvent, :count)
    end
  end

  describe "actions go through Cases::Transition (S2C-013)" do
    it "starts an investigation" do
      patch ops_case_state_path(case_record), params: { state: { to: "investigating" } }

      expect(case_record.reload.status).to eq("investigating")
      expect(case_record.case_events.pluck(:event_type)).to include("investigation_started")
    end

    it "starts a watch with a stated condition (HO §45)" do
      patch ops_case_state_path(case_record),
            params: { state: { to: "watching", watch_condition_type: "time_elapsed", watch_days: "7" } }

      expect(case_record.reload.status).to eq("watching")
      watch = case_record.watch_conditions.last
      expect(watch.condition_type).to eq("time_elapsed")
      expect(watch.expires_at).to be_present
      expect(case_record.watch_until).to be_present
    end

    it "offers only the moves the legality table permits" do
      Cases::Transition.call(case_record: case_record, to: "resolved", actor: operator,
                             disposition: { code: "action_taken" })

      get ops_case_path(case_record)

      expect(response.body).to include("Reopening is not a manual action")
      expect(response.body).not_to include("Start investigating")
    end

    it "refuses an illegal transition and says why" do
      Cases::Transition.call(case_record: case_record, to: "resolved", actor: operator,
                             disposition: { code: "action_taken" })

      patch ops_case_state_path(case_record), params: { state: { to: "investigating" } }

      expect(case_record.reload.status).to eq("resolved")
      expect(flash[:alert]).to include("cannot move")
    end
  end

  describe "S2C-015 closing requires a disposition" do
    it "refuses to resolve without one, and changes nothing" do
      patch ops_case_state_path(case_record), params: { state: { to: "resolved" } }

      expect(case_record.reload.status).to eq("new")
      expect(Cases::Disposition.count).to eq(0)
      expect(flash[:alert]).to include("disposition")
    end

    it "refuses to dismiss without one" do
      patch ops_case_state_path(case_record), params: { state: { to: "dismissed" } }

      expect(case_record.reload.status).to eq("new")
    end

    it "resolves with one, recording it and auditing it" do
      patch ops_case_state_path(case_record),
            params: { state: { to: "resolved", disposition_code: "action_taken",
                               disposition_notes: "Titration adjusted" } }

      expect(case_record.reload.status).to eq("resolved")
      disposition = case_record.latest_disposition
      expect(disposition.code).to eq("action_taken")
      expect(disposition.notes).to eq("Titration adjusted")
      expect(AuditEvent.where(event_type: "case.disposition_entered").count).to eq(1)
    end

    # The server-side refusal above is the control. This is the UI keeping the
    # browser from offering an invalid submit in the first place.
    it "marks the disposition select required in the form" do
      get ops_case_path(case_record)

      form = response.body[/<form[^>]*>(?:(?!<\/form>).)*state\[disposition_code\].*?<\/form>/m]
      expect(form).to include("required")
      expect(form).to include("choose a disposition")
    end

    it "offers only the governed disposition code list (HO §46)" do
      get ops_case_path(case_record)

      expect(response.body).to include("Instrumentation issue")
      expect(response.body).to include("False positive")
    end
  end

  describe "S2C-019 analysis status is shown, never hiding the Case" do
    it "distinguishes a failed analysis from insufficient evidence" do
      case_record.update!(analysis_status: "failed")
      get ops_case_path(case_record)
      expect(response.body).to include("Analysis did not complete")

      case_record.update!(analysis_status: "insufficient_evidence")
      get ops_case_path(case_record)
      expect(response.body).to include("no reliable distinguishing pattern")
      expect(response.body).to include("a result, not a failure")
    end
  end

  describe "HO §84 identity stays opaque" do
    it "shows the public handle and never a name, DOB or MRN" do
      SubjectIdentity.create!(
        subject: subject_record, first_name: "Zephyrine", last_name: "Quattlebaum",
        date_of_birth: "1962-04-11", contact_email: "zq@example.test", contact_phone: "+15551234567"
      )
      SubjectIdentifier.create!(
        organization: organization, subject: subject_record, system: "mrn", value: "MRN-ZQ-99881"
      )
      attach_signal

      get ops_case_path(case_record)

      expect(response.body).to include(subject_record.public_id)
      [ "Zephyrine", "Quattlebaum", "1962-04-11", "zq@example.test", "+15551234567", "MRN-ZQ-99881" ]
        .each { |value| expect(response.body).not_to include(value) }
    end
  end
end
