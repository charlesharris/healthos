# frozen_string_literal: true

module Ops
  # The Ops Queue (HO §84). Read-only in 001-12; assignment, triage and
  # transitions land in 002-21.
  class CasesController < ApplicationController
    def index
      authorize!(Current.organization, :show?, policy_class: OrganizationPolicy)

      @statuses = params[:status].presence || CaseQuery.default_statuses
      @cases = CaseQuery.new(
        organization: Current.organization,
        membership: Current.membership,
        status: @statuses,
        priority: params[:priority].presence,
        domain_key: params[:domain_key].presence
      ).resolve

      @counts = CaseQuery.new(
        organization: Current.organization, membership: Current.membership
      ).counts_by_status
    end
  end
end
