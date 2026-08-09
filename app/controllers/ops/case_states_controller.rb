# frozen_string_literal: true

module Ops
  # Case state changes from Quick Review (HO §87–88).
  #
  # S2C-013: every state change goes through Cases::Transition. This
  # controller reads parameters and hands them over — it does not decide
  # legality, does not write a CaseEvent, and does not touch Case attributes.
  # Transition owns the legality table, the disposition requirement
  # (S2C-015), the timeline entry and the audit row, so no UI path can skip
  # any of them.
  class CaseStatesController < ApplicationController
    def update
      authorize_queue!

      @case_record = case_query_for(params[:case_id]).resolve

      Cases::Transition.call(
        case_record: @case_record, to: state_params[:to], actor: Current.user,
        disposition: disposition, watch: watch
      )

      respond(notice: "Case moved to #{state_params[:to].to_s.humanize.downcase}.")
    rescue Cases::Transition::DispositionRequired, Cases::Transition::InvalidTransition => e
      respond(alert: e.message)
    end

    private

    def state_params
      @state_params ||= (params[:state] || ActionController::Parameters.new)
        .permit(:to, :disposition_code, :disposition_notes, :disposition_action_type,
                :watch_condition_type, :watch_days, :watch_count)
    end

    # Returned only when a code is actually present. Never defaulted: a
    # disposition the system invented would corrupt the resolution feedback
    # loop HO §43 depends on, and Transition refuses the close instead
    # (S2C-015).
    def disposition
      code = state_params[:disposition_code].presence
      return nil if code.nil?

      { code: code, notes: state_params[:disposition_notes].presence,
        action_type: state_params[:disposition_action_type].presence }
    end

    def watch
      type = state_params[:watch_condition_type].presence
      return nil if type.nil?

      {
        condition_type: type,
        parameters: { "count" => state_params[:watch_count].presence&.to_i }.compact,
        expires_at: state_params[:watch_days].presence&.to_i&.days&.from_now
      }
    end

    def respond(notice: nil, alert: nil)
      return refresh_row(notice: notice, alert: alert) if params[:row].present?

      redirect_back fallback_location: ops_case_path(@case_record), status: :see_other,
                    notice: notice, alert: alert
    end
  end
end
