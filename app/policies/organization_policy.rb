# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def show? = active?

  # Only an organization_admin manages the tenant itself.
  def update? = active? && membership.organization_admin?

  def manage_members? = active? && membership.organization_admin?
end
