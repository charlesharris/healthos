# frozen_string_literal: true

module Cases
  # Explicit Signal→Case attachment (HO §38, S2C-009).
  #
  # Append-only: an attachment is a historical fact about how this Case came
  # to include this evidence. Detaching would rewrite that history.
  class CaseSignal < ApplicationRecord
    RELATIONSHIPS = %w[trigger supporting contextual reopening].freeze

    belongs_to :organization
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id, inverse_of: :case_signals
    belongs_to :signal, class_name: "Monitoring::Signal"

    validates :relationship, inclusion: { in: RELATIONSHIPS }
    validates :attached_at, presence: true

    def readonly? = persisted?
  end
end
