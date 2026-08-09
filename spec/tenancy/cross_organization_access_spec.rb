# frozen_string_literal: true

require "rails_helper"

# INV-31 — "Tenant boundaries exist below the UI layer."
# S2C-022 — critical correctness belongs in PostgreSQL, not only in Ruby.
#
# Epic 001-02 requires cross-org denial proven at BOTH the controller and the
# query level. Those are genuinely different claims: a controller check can be
# bypassed by any future code path that calls the query directly, which is
# exactly how tenant leaks happen in practice. So both are asserted here, and
# every tenant-facing surface added from here on is expected to extend this
# file (CLAUDE.md: "Cross-tenant access specs on every new tenant-facing
# surface").
RSpec.describe "Cross-organization access", type: :request do
  let!(:northside) { create_organization(name: "Northside Health", slug: "northside") }
  let!(:southside) { create_organization(name: "Southside Clinic", slug: "southside") }

  let!(:north_user) { create_user(email: "north@example.test") }
  let!(:south_user) { create_user(email: "south@example.test") }

  let!(:north_membership) { create_membership(organization: northside, user: north_user, role: "clinician") }
  let!(:south_membership) { create_membership(organization: southside, user: south_user, role: "clinician") }

  describe "query level" do
    it "returns only the requesting organization's memberships" do
      results = Identity::OrganizationMembersQuery.new(
        organization: northside, membership: north_membership
      ).resolve

      expect(results).to contain_exactly(north_membership)
      expect(results.map(&:organization_id).uniq).to eq([ northside.id ])
    end

    it "cannot be constructed without an organization" do
      expect {
        Identity::OrganizationMembersQuery.new(organization: nil)
      }.to raise_error(Tenanted::Query::MissingOrganizationError)
    end

    # The dangerous case: a caller wires a membership from tenant A to a query
    # for tenant B. Silently narrowing to B would hide the bug, so this raises.
    it "refuses a membership belonging to a different organization" do
      expect {
        Identity::OrganizationMembersQuery.new(
          organization: northside, membership: south_membership
        )
      }.to raise_error(Tenanted::Query::CrossTenantError, /not #{northside.id}/)
    end
  end

  describe "policy level" do
    it "refuses to evaluate a record from another organization" do
      expect {
        OrganizationPolicy.new(membership: north_membership, record: southside)
      }.to raise_error(ApplicationPolicy::CrossTenantError)
    end

    it "denies tenant management to a non-admin" do
      policy = OrganizationPolicy.new(membership: north_membership, record: northside)

      expect(policy.show?).to be(true)
      expect(policy.manage_members?).to be(false)
    end

    it "grants tenant management to an organization_admin" do
      admin = create_membership(organization: northside, role: "organization_admin")
      policy = OrganizationPolicy.new(membership: admin, record: northside)

      expect(policy.manage_members?).to be(true)
    end

    it "grants nothing through a suspended membership" do
      suspended = create_membership(
        organization: northside, role: "organization_admin", status: "suspended"
      )
      policy = OrganizationPolicy.new(membership: suspended, record: northside)

      expect(policy.show?).to be(false)
      expect(policy.manage_members?).to be(false)
    end
  end

  describe "controller level" do
    it "shows only the signed-in user's organization members" do
      sign_in north_user
      get members_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("north@example.test")
      expect(response.body).not_to include("south@example.test")
    end

    it "refuses to switch into an organization the user is not a member of" do
      sign_in north_user
      post choose_organization_path(organization_id: southside.id)

      expect(response).to have_http_status(:not_found)
    end

    # A suspended membership must lose access on the next request, not
    # whenever the session happens to expire — which is why the membership is
    # re-resolved from the database per request rather than trusted from the
    # cookie.
    it "revokes access as soon as the membership is suspended" do
      sign_in north_user
      get members_path
      expect(response).to have_http_status(:ok)

      north_membership.update!(status: "suspended")

      get members_path
      expect(response).to redirect_to(no_access_path)
    end

    it "redirects an unauthenticated visitor to sign in" do
      get members_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "database level (S2C-022)" do
    it "rejects a duplicate membership even when Ruby validation is skipped" do
      duplicate = OrganizationMembership.new(
        organization: northside, user: north_user, role: "analyst"
      )

      expect {
        duplicate.save!(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects an invalid role even when Ruby validation is skipped" do
      membership = OrganizationMembership.new(
        organization: northside, user: create_user, role: "root"
      )

      expect {
        membership.save!(validate: false)
      }.to raise_error(ActiveRecord::StatementInvalid, /organization_memberships_role_check/)
    end

    it "rejects a team membership that crosses organizations" do
      north_team = Team.create!(organization: northside, name: "Cardiology")
      crossing = TeamMembership.new(
        organization: northside, team: north_team, organization_membership: south_membership
      )

      expect(crossing).not_to be_valid
      expect(crossing.errors.full_messages.join).to match(/same organization/)
    end
  end
end
