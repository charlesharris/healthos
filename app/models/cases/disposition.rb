# frozen_string_literal: true

module Cases
  # What happened when work closed (HO §46, S2C-015).
  #
  # Append-only, and a separate record rather than a column on the Case:
  # S2C-016 requires a reopened Case to keep its prior disposition visible,
  # and a column would be overwritten on the second resolution.
  class Disposition < ApplicationRecord
    self.table_name = "case_dispositions"

    CODES = %w[
      action_taken expected_change instrumentation_issue data_quality_issue
      already_known not_actionable insufficient_evidence duplicate
      false_positive escalated_external
    ].freeze

    # HO §43's resolution feedback loop reads these. A Case closed
    # `false_positive` or `instrumentation_issue` says something about the
    # monitor that produced it, which is what makes monitor quality
    # measurable (HO §129).
    MONITOR_QUALITY_SIGNALS = %w[false_positive instrumentation_issue data_quality_issue].freeze

    belongs_to :organization
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id, inverse_of: :dispositions
    belongs_to :actor, class_name: "User"

    validates :code, inclusion: { in: CODES }
    validates :disposed_at, presence: true

    def readonly? = persisted?

    def indicates_monitor_problem? = MONITOR_QUALITY_SIGNALS.include?(code)
  end
end
