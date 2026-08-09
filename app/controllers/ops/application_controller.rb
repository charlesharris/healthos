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
    def refresh_row(notice: nil, alert: nil)
      flash.now[:notice] = notice if notice
      flash.now[:alert] = alert if alert

      render turbo_stream: [
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@case_record, :row),
          partial: "ops/cases/case_row", locals: { case_record: @case_record.reload }
        ),
        turbo_stream.replace("queue_flash", partial: "ops/cases/flash")
      ]
    end
  end
end
