# frozen_string_literal: true

module Cases
  # Provider access audit for Case surfaces (HO §92, §157; INV-32).
  #
  # Separate from the workflow timeline, and the distinction is not
  # bookkeeping. CaseEvent answers "what happened to this Case" and is part of
  # the product — an operator reads it. AuditEvent answers "who looked at
  # what" and is a compliance record; it is not shown in the UI and is
  # append-only at the database.
  #
  # The clearest case for keeping them apart: VIEWING a Case produces an audit
  # event and no case event. A timeline that filled with "Dr X looked at this"
  # would drown the workflow history it exists to show, and would leak who is
  # reviewing whom to everyone with queue access.
  module Audit
    module_function

    # HO §92's list, restricted to what exists today. Named constants rather
    # than free strings so a typo is a load error and the audit trail stays
    # queryable — an audit you cannot aggregate is an audit you cannot answer
    # a regulator with.
    EVENT_TYPES = {
      case_viewed: "case.viewed",
      case_assigned: "case.assigned",
      case_state_changed: "case.state_changed",
      disposition_entered: "case.disposition_entered",
      subject_identity_viewed: "subject.identity_viewed",
      evidence_expanded: "case.evidence_expanded"
    }.freeze

    def record!(event, case_record:, actor:, metadata: {})
      AuditEvent.record!(
        event_type: EVENT_TYPES.fetch(event),
        actor: actor,
        organization: case_record.organization,
        metadata: {
          # Ids only. HO §92: "avoid raw PHI in audit metadata unless
          # required" — and it is not required here, because the ids resolve.
          "case_id" => case_record.id,
          "case_public_id" => case_record.public_id,
          "subject_id" => case_record.subject_id
        }.merge(metadata.stringify_keys)
      )
    end

    # Subject identity is the one read HO §92 names explicitly, because it is
    # the moment a provider goes from working with an opaque handle to seeing
    # a person.
    def record_identity_view!(subject:, actor:, organization:)
      AuditEvent.record!(
        event_type: EVENT_TYPES.fetch(:subject_identity_viewed),
        actor: actor, organization: organization,
        metadata: { "subject_id" => subject.id, "subject_public_id" => subject.public_id }
      )
    end
  end
end
