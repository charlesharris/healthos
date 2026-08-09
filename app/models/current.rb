# frozen_string_literal: true

# Per-request context (HO §12 application layer).
#
# `Current` is a convenience for controllers, NOT an ambient authority.
# Queries and services must take an explicit organization argument rather than
# reading Current themselves — HO §12: "All tenant-facing queries require
# organization context", and "avoid global unscoped health-data finders in
# controllers". Reading Current deep in a query object reintroduces exactly
# the ambient tenancy that requirement exists to prevent, and it is invisible
# in a method signature.
#
# The rule this codebase follows: Current is read at the controller boundary
# and passed down as an argument. See Tenanted::Query.
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :membership

  delegate :user, to: :session, allow_nil: true

  # The active tenant, derived from the membership rather than stored
  # separately, so the two can never disagree.
  def organization
    membership&.organization
  end
end
