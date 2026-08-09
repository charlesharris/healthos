# frozen_string_literal: true

module Tenanted
  # Base class for every query that touches tenant-scoped data.
  #
  # Two requirements converge here:
  #
  #   HO §12  "All tenant-facing queries require organization context" and
  #           "avoid global unscoped health-data finders in controllers".
  #   ADR-001 The query-object gateway is the seam that makes a future
  #           columnar migration a repoint rather than a rewrite. It only
  #           works if reads actually go through it.
  #
  # Organization is a required constructor argument, not something read from
  # Current. That makes tenancy visible in the signature and testable without
  # a request, and it means a query cannot silently inherit whatever tenant
  # happened to be set on the current thread.
  #
  # Subclasses implement #scope and get #resolve for free.
  class Query
    class MissingOrganizationError < ArgumentError; end
    class CrossTenantError < StandardError; end

    attr_reader :organization, :membership

    def initialize(organization:, membership: nil)
      raise MissingOrganizationError, "organization is required" if organization.blank?

      @organization = organization
      @membership = membership

      return if membership.nil? || membership.organization_id == organization.id

      # A membership from a different tenant is never a legitimate state; it
      # means a caller wired two contexts together incorrectly. Fail loudly
      # rather than silently narrowing to the organization.
      raise CrossTenantError,
        "membership belongs to organization #{membership.organization_id}, not #{organization.id}"
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end

    private

    # Every subclass scopes through this rather than writing `where` by hand,
    # so the tenant predicate cannot be forgotten.
    def for_tenant(relation)
      relation.where(organization_id: organization.id)
    end
  end
end
