# frozen_string_literal: true

module Ops
  # Case assignment from the queue or from Quick Review (HO §87).
  #
  # Delegates to Cases::Assign. The controller resolves parameters into
  # records and nothing else: it never touches Case attributes, so the
  # workflow history and the access audit cannot be bypassed by a form
  # (S2C-013's rule, applied to assignment as well as to state).
  class AssignmentsController < ApplicationController
    def update
      authorize_queue!

      @case_record = case_query_for(params[:case_id]).resolve

      Cases::Assign.call(
        case_record: @case_record, actor: Current.user,
        owner: resolved(:owner_id, assignment_options.owners),
        team: resolved(:team_id, assignment_options.teams)
      )

      respond(notice: "Assignment updated.")
    rescue Cases::Assign::NotAssignable => e
      respond(alert: e.message)
    end

    private

    # Three-way: absent parameter leaves the field alone, an empty string
    # unassigns, an id assigns. Only ids the tenant actually offers are
    # accepted — an id from elsewhere is refused rather than looked up
    # globally.
    def resolved(key, candidates)
      return Cases::Assign::UNCHANGED unless params.key?(:assignment) && params[:assignment].key?(key)

      value = params[:assignment][key].presence
      return nil if value.nil?

      candidates.find { |candidate| candidate.id == value } ||
        raise(Cases::Assign::NotAssignable, "#{key} is not assignable in this organization")
    end

    # Turbo replaces the single row the form came from (HO §87 "live/near-live
    # row refresh"). Keyed off an explicit `row` field rather than content
    # negotiation, because Turbo Drive sends the same Accept header from the
    # Quick Review page — where the right answer is a full redirect, not a
    # stream aimed at a row that is not on screen.
    def respond(notice: nil, alert: nil)
      return refresh_row(notice: notice, alert: alert) if params[:row].present?

      redirect_back fallback_location: ops_cases_path, status: :see_other,
                    notice: notice, alert: alert
    end
  end
end
