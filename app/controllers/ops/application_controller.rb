# frozen_string_literal: true

module Ops
  # Shared base for the Ops Queue surfaces (HO §84–88).
  #
  # Everything tenant-facing here loads through a Tenanted::Query with an
  # explicit organization (INV-31) — there is no `Cases::CaseRecord.find` in
  # this namespace, and a Case id belonging to another organization simply
  # does not resolve.
  class ApplicationController < ::ApplicationController
    private

    def authorize_queue!
      authorize!(Current.organization, :show?, policy_class: CasePolicy)
    end

    def case_query_for(id)
      CaseDetailQuery.new(
        organization: Current.organization, membership: Current.membership, id: id
      )
    end

    def assignment_options
      @assignment_options ||= AssignmentOptionsQuery.new(
        organization: Current.organization, membership: Current.membership
      )
    end
    helper_method :assignment_options

    # HO §87: "live/near-live row refresh". One row, re-rendered from the
    # database, so the queue does not have to reload to show what changed.
    #
    # When the action came from the Quick Review drawer the panel is refreshed
    # in the same stream: acting on a Case must not leave the panel showing
    # the state the Case was in before the act, and the row behind it must not
    # disagree with the panel in front of it.
    def refresh_row(notice: nil, alert: nil)
      flash.now[:notice] = notice if notice
      flash.now[:alert] = alert if alert

      streams = [
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@case_record, :row),
          partial: "ops/cases/case_row", locals: { case_record: @case_record.reload }
        ),
        turbo_stream.replace("queue_flash", partial: "ops/cases/flash")
      ]
      streams << drawer_stream if params[:drawer].present?

      render turbo_stream: streams
    end

    # Re-resolved through CaseDetailQuery rather than reusing the record in
    # hand, so the panel is rebuilt from the same tenant-scoped read path as a
    # direct visit — including the attachments and timeline the act may have
    # just added.
    def drawer_stream
      detail = case_query_for(@case_record.id)
      case_record = detail.resolve

      turbo_stream.replace(
        "case_drawer",
        partial: "ops/cases/drawer_frame",
        locals: { case_record: case_record,
                  trigger_attachments: detail.trigger_attachments,
                  other_attachments: detail.other_attachments,
                  timeline: detail.timeline,
                  telemetry: detail.telemetry_profile(
                    semantic_key: params[:key].presence,
                    selection: TelemetryProfileQuery::Selection.from_params(params)
                  ) }
      )
    end
  end
end
