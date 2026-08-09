# frozen_string_literal: true

# Minimal tenant UI for epic 001-02: choose an active organization, and view
# the member list. Deliberately thin — the Ops Queue (epic 002) is the real
# product surface.
class OrganizationsController < ApplicationController
  allow_without_organization only: %i[chooser choose no_access]

  def chooser
    @memberships = Current.user.usable_memberships.includes(:organization)
  end

  def choose
    membership = Current.user.usable_memberships.find_by(organization_id: params[:organization_id])

    # find_by rather than find, scoped to the user's own memberships: an
    # unknown or unauthorized id must be indistinguishable from a
    # nonexistent one (HO §123 ID enumeration).
    raise ActiveRecord::RecordNotFound if membership.nil?

    session[:organization_id] = membership.organization_id
    redirect_to members_path
  end

  def no_access; end

  def members
    authorize!(Current.organization, :show?, policy_class: OrganizationPolicy)

    @memberships = Identity::OrganizationMembersQuery.new(
      organization: Current.organization,
      membership: Current.membership
    ).resolve
  end
end
