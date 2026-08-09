# frozen_string_literal: true

require "rails_helper"

# Quick Review as a panel over the queue (HO §87, §88, §92).
#
# The drawer is presentation, but it is presentation with a server contract:
# one controller action serves both the panel and the standalone page, and an
# action taken inside the panel has to leave the panel and the queue row
# behind it agreeing with each other.
#
# The rule these specs hold down is that the drawer adds no second code path.
# Same action, same authorization, same audit — only the envelope differs.
RSpec.describe "Quick Review drawer", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_organization) { create_organization(name: "Southside", slug: "southside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:operator) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: operator, role: "clinical_ops") }

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

  let(:frame_headers) { { "Turbo-Frame" => "case_drawer" } }

  before { sign_in operator }

  describe "rendering" do
    it "renders the panel inside the queue's frame when the queue asks for it" do
      get ops_case_path(case_record), headers: frame_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<turbo-frame id="case_drawer"))
      expect(response.body).to include("Blood pressure pattern change")
      expect(response.body).to include("Why is this here?")
    end

    # The panel is an overlay on the queue, so it must not drag the queue's
    # own chrome in with it — two rails and two top bars on one screen.
    it "omits the application shell from the panel" do
      get ops_case_path(case_record), headers: frame_headers

      expect(response.body).not_to include(%(class="rail"))
      expect(response.body).not_to include(%(class="topbar"))
    end

    it "offers a way out of the panel to the standalone page" do
      get ops_case_path(case_record), headers: frame_headers

      expect(response.body).to include("Open full review")
      expect(response.body).to include(ops_case_path(case_record))
    end

    # HO §88's surface has to survive without JavaScript and be linkable, so
    # the same URL renders a whole page when it is asked for one.
    it "renders the full page with shell and breadcrumb on a direct visit" do
      get ops_case_path(case_record)

      expect(response.body).to include(%(class="rail"))
      expect(response.body).to include("Ops Queue")
      expect(response.body).not_to include(%(<turbo-frame id="case_drawer"))
    end

    # HO §92: viewing a Case is a provider ACCESS event however it is framed.
    # A panel that skipped the audit would be a way to read Cases unobserved.
    it "audits a panel view exactly as it audits a page view" do
      expect { get ops_case_path(case_record), headers: frame_headers }
        .to change(AuditEvent.where(event_type: "case.viewed"), :count).by(1)
    end

    # INV-31 does not care what the response is wrapped in.
    it "does not resolve another organization's Case through the frame" do
      foreign_subject = Subject.create!(organization: other_organization, timezone: "UTC")
      foreign_case = Cases::CaseRecord.create!(
        organization: other_organization, subject: foreign_subject,
        domain_key: "hypertension", case_type: "blood_pressure_change",
        status: "new", review_priority: "today",
        started_at: now - 7.days, detected_at: now
      )

      get ops_case_path(foreign_case), headers: frame_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "acting from the panel" do
    let(:stream_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

    # The panel and the row behind it are two views of one Case. Refreshing
    # only one of them leaves the operator looking at a contradiction.
    it "refreshes the row, the flash and the panel in one stream" do
      patch ops_case_state_path(case_record),
            params: { row: "1", drawer: "1", state: { to: "triaged" } },
            headers: stream_headers

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(case_record, :row)}"))
      expect(response.body).to include(%(target="queue_flash"))
      expect(response.body).to include(%(target="case_drawer"))
    end

    it "rebuilds the panel with the new state rather than the state it acted on" do
      patch ops_case_state_path(case_record),
            params: { row: "1", drawer: "1", state: { to: "triaged" } },
            headers: stream_headers

      expect(case_record.reload.status).to eq("triaged")
      expect(response.body).to include("Triaged")
      # `new` is the only status offering this move, so its absence proves the
      # panel was re-rendered rather than replayed.
      expect(response.body).not_to include("Triage</button>")
    end

    it "streams the panel for assignment too" do
      colleague = create_user(email: "colleague@example.test")
      create_membership(organization: organization, user: colleague, role: "clinician")

      patch ops_case_assignment_path(case_record),
            params: { row: "1", drawer: "1", assignment: { owner_id: colleague.id } },
            headers: stream_headers

      expect(response.body).to include(%(target="case_drawer"))
      expect(response.body).to include("colleague@example.test")
      expect(case_record.reload.owner).to eq(colleague)
    end

    # A refused move still has to leave both views coherent — and still has to
    # say why (S2C-015).
    it "streams the panel and the reason when the move is refused" do
      patch ops_case_state_path(case_record),
            params: { row: "1", drawer: "1", state: { to: "resolved" } },
            headers: stream_headers

      expect(case_record.reload.status).to eq("new")
      expect(response.body).to include(%(target="queue_flash"))
      expect(response.body).to include(%(target="case_drawer"))
      expect(response.body).to include("disposition")
    end

    # The queue's own inline controls send `row` without `drawer`; nothing
    # about the panel should leak into that response.
    it "leaves the row-only refresh untouched" do
      patch ops_case_state_path(case_record),
            params: { row: "1", state: { to: "triaged" } },
            headers: stream_headers

      expect(response.body).to include(%(target="queue_flash"))
      expect(response.body).not_to include(%(target="case_drawer"))
    end

    # Without JavaScript there is no panel and no stream — just a redirect.
    it "still redirects when neither row nor drawer is sent" do
      patch ops_case_state_path(case_record), params: { state: { to: "triaged" } }

      expect(response).to have_http_status(:see_other)
      expect(case_record.reload.status).to eq("triaged")
    end
  end
end
