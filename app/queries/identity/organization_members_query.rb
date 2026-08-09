# frozen_string_literal: true

module Identity
  # First concrete tenanted query. Exists mainly so the cross-tenant specs
  # have a real query to exercise rather than asserting against a base class.
  class OrganizationMembersQuery < Tenanted::Query
    def resolve
      for_tenant(OrganizationMembership.all)
        .includes(:user)
        .order("users.email_address")
    end
  end
end
