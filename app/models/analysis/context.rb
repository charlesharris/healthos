# frozen_string_literal: true

module Analysis
  # A materialized analytical Context (HO §52).
  #
  # Immutable once written (INV-13/14, HO §50). Late data does not rewrite a
  # Context; it marks the Case analysis stale and a NEW Context is built, with
  # the Case's `current_context_id` pointer moving to it (HO §99). That is
  # what lets a saved Investigation keep meaning what it meant
  # (STAT-040/041).
  class Context < ApplicationRecord
    self.table_name = "contexts"

    belongs_to :organization
    belongs_to :subject
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id,
      optional: true, inverse_of: false
    belongs_to :input_evidence_set, class_name: "EvidenceSet", optional: true
    has_many :context_values, class_name: "Analysis::ContextValue", dependent: :restrict_with_error,
      inverse_of: :context

    validates :definition_key, :definition_version, :definition_digest,
      :anchor_type, :window_started_at, :window_ended_at, :as_of, :fingerprint, presence: true
    validates :status, inclusion: { in: %w[materialized insufficient_input failed] }

    scope :materialized, -> { where(status: "materialized") }

    def readonly? = persisted?

    def definition = "#{definition_key}@v#{definition_version}"

    def value_for(dimension_key)
      context_values.find { |v| v.dimension_key == dimension_key }
    end

    # INV-3: the exact inputs this Context was computed from.
    def inputs = input_evidence_set ? input_evidence_set.resolve : []
  end
end
