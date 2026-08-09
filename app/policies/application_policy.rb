# frozen_string_literal: true

# Policy-object authorization skeleton (HO §11: "Use policy objects for
# authorization").
#
# A policy always answers in the context of a membership, never a bare user,
# because role lives on the membership (HO §10.2). Constructing a policy for a
# record outside the membership's organization is a programming error and
# raises rather than returning false — a silent false would hide the bug and
# read as a legitimate permission denial.
class ApplicationPolicy
  class CrossTenantError < StandardError; end

  attr_reader :membership, :record

  def initialize(membership:, record: nil)
    @membership = membership
    @record = record

    guard_same_tenant!
  end

  def show? = false
  def create? = false
  def update? = false
  def destroy? = false

  private

  def organization = membership&.organization

  def role = membership&.role

  def active? = membership.present? && membership.active?

  def guard_same_tenant!
    return if record.nil? || membership.nil?

    record_org_id = tenant_id_for(record)
    return if record_org_id.nil?
    return if record_org_id == membership.organization_id

    raise CrossTenantError,
      "#{record.class} #{record.id} belongs to another organization"
  end

  # The Organization itself is the one record whose tenant key is its own id
  # rather than an organization_id column. Missing that case made the guard
  # silently skip the most important record of all, so it is handled
  # explicitly rather than by duck-typing on `organization_id`.
  def tenant_id_for(record)
    return record.id if record.is_a?(Organization)

    record.organization_id if record.respond_to?(:organization_id)
  end
end
