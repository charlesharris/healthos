# frozen_string_literal: true

# An outward action requested from a Case (HO §91).
#
# The row is durable intent; dispatch is a separate retryable step, because
# S2C-024 forbids external calls inside a transaction. Same shape as the
# outbox, for the same reason. The adapter lands with 005-06.
class WorkflowAction < ApplicationRecord
  STATUSES = %w[pending dispatched succeeded failed cancelled].freeze

  belongs_to :organization
  belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id, inverse_of: false
  belongs_to :requested_by, class_name: "User", optional: true

  validates :action_type, :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }
end
