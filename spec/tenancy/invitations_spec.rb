# frozen_string_literal: true

require "rails_helper"

# HO §11 v0.1: invitation-based organization membership.
RSpec.describe "Invitations", type: :request do
  let!(:organization) { create_organization(name: "Northside Health", slug: "northside") }
  let!(:other_org) { create_organization(name: "Southside Clinic", slug: "southside") }
  let!(:admin_user) { create_user(email: "admin@example.test") }
  let!(:admin) { create_membership(organization: organization, user: admin_user, role: "organization_admin") }

  describe "token handling" do
    it "never persists the raw token" do
      _invitation, raw = Invitation.issue!(
        organization: organization, email_address: "new@example.test",
        role: "clinician", invited_by: admin_user
      )

      expect(Invitation.where(token_digest: raw)).to be_empty
      expect(Invitation.last.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(Invitation.last.attributes.values).not_to include(raw)
    end

    it "finds an outstanding invitation by raw token" do
      invitation, raw = Invitation.issue!(
        organization: organization, email_address: "new@example.test",
        role: "clinician", invited_by: admin_user
      )

      expect(Invitation.find_outstanding_by_token(raw)).to eq(invitation)
    end

    it "does not find an expired invitation" do
      _invitation, raw = Invitation.issue!(
        organization: organization, email_address: "new@example.test",
        role: "clinician", invited_by: admin_user, validity: -1.day
      )

      expect(Invitation.find_outstanding_by_token(raw)).to be_nil
    end
  end

  describe "acceptance" do
    it "creates an active membership with the invited role" do
      invitation, raw = Invitation.issue!(
        organization: organization, email_address: "nurse@example.test",
        role: "clinical_ops", invited_by: admin_user
      )

      get accept_invitation_path(token: raw)
      expect(response).to have_http_status(:ok)

      post invitations_accept_path, params: { token: raw, password: "a good long password" }

      membership = OrganizationMembership.joins(:user).find_by(users: { email_address: "nurse@example.test" })
      expect(membership.organization).to eq(organization)
      expect(membership.role).to eq("clinical_ops")
      expect(membership.status).to eq("active")
      expect(invitation.reload.accepted_at).to be_present
    end

    it "cannot be replayed once accepted" do
      _invitation, raw = Invitation.issue!(
        organization: organization, email_address: "nurse@example.test",
        role: "clinician", invited_by: admin_user
      )
      post invitations_accept_path, params: { token: raw, password: "a good long password" }

      expect(Invitation.find_outstanding_by_token(raw)).to be_nil
    end

    # An unknown, expired and already-consumed token must be indistinguishable
    # so a guesser learns nothing (HO §123 lists ID enumeration explicitly).
    it "returns 404 for an unknown token" do
      get accept_invitation_path(token: "not-a-real-token")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authorization" do
    it "lets an organization_admin invite" do
      sign_in admin_user
      post invitations_path, params: { email_address: "new@example.test", role: "clinician" }

      expect(Invitation.count).to eq(1)
      expect(Invitation.last.organization).to eq(organization)
    end

    it "refuses a non-admin member" do
      clinician = create_user(email: "clinician@example.test")
      create_membership(organization: organization, user: clinician, role: "clinician")

      sign_in clinician
      post invitations_path, params: { email_address: "new@example.test", role: "clinician" }

      expect(response).to have_http_status(:not_found)
      expect(Invitation.count).to eq(0)
    end

    # The invitation is bound to the inviter's tenant, so an admin cannot
    # grant access to an organization they do not administer.
    it "scopes a created invitation to the admin's own organization" do
      sign_in admin_user
      post invitations_path, params: { email_address: "new@example.test", role: "clinician" }

      expect(Invitation.last.organization).to eq(organization)
      expect(Invitation.last.organization).not_to eq(other_org)
    end

    it "lists only the current organization's invitations" do
      Invitation.issue!(organization: organization, email_address: "ours@example.test",
        role: "clinician", invited_by: admin_user)
      Invitation.issue!(organization: other_org, email_address: "theirs@example.test",
        role: "clinician", invited_by: admin_user)

      sign_in admin_user
      get invitations_path

      expect(response.body).to include("ours@example.test")
      expect(response.body).not_to include("theirs@example.test")
    end
  end
end
