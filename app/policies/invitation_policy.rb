# frozen_string_literal: true

class InvitationPolicy < ApplicationPolicy
  # Only an organization_admin may invite. HO §11 keeps roles coarse; this is
  # the one membership-management capability v0.1 needs.
  def create? = active? && membership.organization_admin?
  def index?  = create?
end
