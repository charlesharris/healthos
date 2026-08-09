# frozen_string_literal: true

require "rails_helper"

# The admin UI is a deliberate, narrow exception to INV-31 — staff read across
# organizations. These specs are what keep the exception narrow.
#
# The scope guard matters most over time. Re-running `administrate:install`
# generates a dashboard for every model it finds, so the day `observations` or
# `subjects` exists, a careless regeneration would silently expose health
# evidence through a generic CRUD surface. This fails the build instead.
RSpec.describe "Admin UI scope", type: :request do
  # Tables the admin UI must never expose. Health evidence, PHI, and the
  # analytical artifacts. These get purpose-built read-only tooling instead
  # (HO §157; provenance drilldown in 001-08, support tooling in 005-15).
  FORBIDDEN_RESOURCES = %w[
    subjects subject_identities subject_identifiers
    raw_envelopes observations observation_groups events intervals
    derived_signals evidence_sets evidence_items
    monitor_evaluations signals
    cases case_signals case_events case_dispositions case_correlation_scopes
    contexts context_values baseline_instances comparisons differences
    findings finding_differences investigations
  ].freeze

  describe "dashboard coverage" do
    it "has no dashboard for any health-evidence resource" do
      dashboards = Rails.root.glob("app/dashboards/*_dashboard.rb").map do |path|
        File.basename(path, "_dashboard.rb").pluralize
      end

      exposed = dashboards & FORBIDDEN_RESOURCES

      expect(exposed).to be_empty,
        "The admin UI must not expose health evidence: #{exposed.join(', ')}. " \
        "Delete these dashboards. Evidence inspection is served by the " \
        "purpose-built tooling in HO §157, not by generic CRUD."
    end

    it "has no admin controller for any health-evidence resource" do
      controllers = Rails.root.glob("app/controllers/admin/*_controller.rb").map do |path|
        File.basename(path, "_controller.rb")
      end

      exposed = controllers & FORBIDDEN_RESOURCES

      expect(exposed).to be_empty,
        "Delete these admin controllers: #{exposed.join(', ')}"
    end

    it "routes no admin path to a health-evidence resource" do
      admin_controllers = Rails.application.routes.routes
        .map { |r| r.defaults[:controller] }
        .compact
        .select { |c| c.start_with?("admin/") }
        .map { |c| c.delete_prefix("admin/") }
        .uniq

      expect(admin_controllers & FORBIDDEN_RESOURCES).to be_empty
    end
  end

  describe "access control" do
    let!(:organization) { create_organization(name: "Northside", slug: "northside") }
    let!(:user) { create_user(email: "user@example.test") }
    let!(:membership) { create_membership(organization: organization, user: user, role: "organization_admin") }

    it "redirects an unauthenticated visitor to sign in" do
      get admin_root_path

      expect(response).to redirect_to(new_session_path)
    end

    # An organization_admin is a tenant role, not a platform one. Being the
    # most privileged user inside an organization grants nothing here.
    it "returns 404 for a signed-in user who is not staff" do
      sign_in user
      get admin_root_path

      expect(response).to have_http_status(:not_found)
    end

    it "admits an active staff member" do
      StaffMember.create!(user: user, status: "active")

      sign_in user
      get admin_root_path

      expect(response).to have_http_status(:ok)
    end

    it "refuses a revoked staff member" do
      StaffMember.create!(user: user, status: "revoked", revoked_at: Time.current)

      sign_in user
      get admin_root_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "append-only resources" do
    let!(:organization) { create_organization(name: "Northside", slug: "northside") }
    let!(:user) { create_user(email: "staff@example.test") }
    let!(:staff) { StaffMember.create!(user: user, status: "active") }

    before { sign_in user }

    it "lists audit events read-only" do
      AuditEvent.record!(event_type: "admin.test", actor: user, organization: organization)

      get admin_audit_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/href="[^"]*audit_events\/new/)
    end

    # audit_events is append-only at the database level, so even if the UI
    # offered this the grant would refuse it (ADR-002 4a). The UI should not
    # offer it either.
    it "refuses to render the new-audit-event form" do
      get new_admin_audit_event_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "auditing (HO §92, §157)" do
    let!(:user) { create_user(email: "staff@example.test") }
    let!(:staff) { StaffMember.create!(user: user, status: "active") }

    before { sign_in user }

    it "records an audit event when staff create a resource" do
      expect {
        post admin_organizations_path, params: {
          organization: { name: "New Clinic", slug: "new-clinic", status: "active" }
        }
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:occurred_at).last
      expect(event.event_type).to eq("admin.organizations.create")
      expect(event.actor).to eq(user)
      expect(event.staff_member).to eq(staff)
    end

    it "records field names but never values in audit metadata" do
      post admin_organizations_path, params: {
        organization: { name: "Sensitive Name", slug: "sensitive", status: "active" }
      }

      event = AuditEvent.order(:occurred_at).last
      expect(event.metadata["changed_fields"]).to include("name", "slug")
      expect(event.metadata.to_json).not_to include("Sensitive Name")
    end
  end

  describe "database role" do
    # The admin UI must not run as healthos_admin, which can delete from
    # append-only tables. Running as healthos_app means no admin screen can
    # mutate evidence even if one were added by mistake.
    it "runs as the unprivileged application role" do
      expect(ActiveRecord::Base.connection.select_value("SELECT current_user"))
        .to eq("healthos_app")
    end
  end
end
