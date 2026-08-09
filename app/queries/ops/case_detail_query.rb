# frozen_string_literal: true

module Ops
  # One Case, for Quick Review (HO §88) and for the action controllers.
  #
  # A Tenanted::Query rather than a bare `find` in the controller (INV-31,
  # HO §12). The tenant predicate is in the WHERE clause, so a Case id from
  # another organization does not resolve at all — ApplicationController turns
  # the resulting RecordNotFound into a 404, which also refuses to confirm
  # that the id exists somewhere else (HO §123).
  class CaseDetailQuery < Tenanted::Query
    def initialize(organization:, id:, membership: nil)
      super(organization: organization, membership: membership)
      @id = id
    end

    def resolve
      @case_record ||= for_tenant(Cases::CaseRecord.all)
        .includes(:subject, :owner, :team)
        .find_by!(id: @id)
    end

    # "Why is this here?" (HO §88). The attachments in the order they were
    # made, with the Signal and the persisted correlation explanation (§158),
    # so the answer is the actual evidence rather than a restatement of the
    # Case title.
    def signal_attachments
      resolve.case_signals.includes(:signal).order(:attached_at)
    end

    def trigger_attachments
      signal_attachments.select { |attachment| attachment.relationship == "trigger" }
    end

    def other_attachments
      signal_attachments.reject { |attachment| attachment.relationship == "trigger" }
    end

    def timeline
      Cases::TimelineQuery.new(
        organization: organization, membership: membership, case_record: resolve
      ).resolve
    end
  end
end
