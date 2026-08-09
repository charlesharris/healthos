# frozen_string_literal: true

module Ops
  # Who a Case can be assigned to, and which teams exist (HO §87 assignment).
  #
  # A tenanted query rather than `Team.where(...)` in the controller (INV-31).
  # It also decides who is *offerable*: only active memberships with clinical
  # access, because assigning health work to a support_limited membership
  # would create an owner who cannot open what they own (HO §157 wants
  # support access audited and narrow, not implicit).
  class AssignmentOptionsQuery < Tenanted::Query
    def resolve
      { owners: owners, teams: teams }
    end

    def owners
      @owners ||= for_tenant(OrganizationMembership.active)
        .includes(:user)
        .select { |membership| membership.clinical_access? }
        .map(&:user)
        .sort_by(&:email_address)
    end

    def teams
      @teams ||= for_tenant(Team.active).order(:name).to_a
    end
  end
end
