# frozen_string_literal: true

module Ops
  # The Ops Queue and Quick Review (HO §84–88).
  #
  # Read-only by construction. Every mutation this surface offers lives in a
  # sibling controller that delegates to a service: assignment to
  # Cases::Assign, state to Cases::Transition (S2C-013). There is no
  # `update!` in app/controllers/ops — spec/ops/controller_invariants_spec.rb
  # greps for it.
  class CasesController < ApplicationController
    # Tabs are statuses plus two aggregates. "Active" is the default because
    # the queue is a to-do list; resolved and dismissed work is history and
    # has to be asked for (HO §84).
    ACTIVE_TAB = "active"
    ALL_TAB = "all"

    def index
      authorize_queue!

      @tab = resolve_tab
      @query = CaseQuery.new(
        organization: Current.organization,
        membership: Current.membership,
        status: statuses_for(@tab),
        priority: params[:priority].presence,
        owner: owner_filter,
        team: team_filter,
        domain_key: params[:domain_key].presence,
        case_type: params[:case_type].presence,
        sort: params[:sort],
        page: params[:page],
        per_page: params[:per_page]
      )

      @cases = @query.resolve
      @counts = @query.counts_by_status
    end

    # Quick Review (HO §88). Most Cases should be resolvable here without
    # opening the Workbench.
    def show
      authorize_queue!

      detail = case_query_for(params[:id])
      @case_record = detail.resolve

      # HO §92: viewing a Case is a provider ACCESS event. It writes an
      # AuditEvent and deliberately no CaseEvent — a workflow timeline full of
      # "Dr X looked at this" would drown the history it exists to show, and
      # would leak who is reviewing whom to everyone with queue access.
      Cases::Audit.record!(:case_viewed, case_record: @case_record, actor: Current.user)

      @trigger_attachments = detail.trigger_attachments
      @other_attachments = detail.other_attachments
      @timeline = detail.timeline

      # Descriptive only, and explicitly not an analytical artifact — see
      # TelemetryProfileQuery. `semantic_key` lets an operator switch which
      # measure is plotted; the query ignores a key the subject has no data
      # for rather than rendering an empty chart for a typo.
      @telemetry = detail.telemetry_profile(
        semantic_key: params[:key].presence,
        selection: TelemetryProfileQuery::Selection.from_params(params)
      )
    end

    private

    def resolve_tab
      requested = params[:status].presence || ACTIVE_TAB
      return requested if requested.in?([ ACTIVE_TAB, ALL_TAB ])
      return requested if requested.in?(Cases::CaseRecord::STATUSES)

      ACTIVE_TAB
    end

    def statuses_for(tab)
      case tab
      when ALL_TAB then nil
      when ACTIVE_TAB then CaseQuery.default_statuses
      else [ tab ]
      end
    end

    # "unassigned" is a first-class filter, not the absence of one: unclaimed
    # work is the question a shift lead asks most often. "me" is the other.
    def owner_filter
      value = params[:owner].presence
      return nil if value.nil?
      return CaseQuery::UNASSIGNED if value == CaseQuery::UNASSIGNED
      return Current.user.id if value == "me"

      value
    end

    def team_filter = params[:team].presence
  end
end
