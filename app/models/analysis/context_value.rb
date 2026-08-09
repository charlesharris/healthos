# frozen_string_literal: true

module Analysis
  # One dimension of a Context (HO §53).
  #
  # Carries its own difference-family metadata (SC §49-50) so that
  # correlated-family suppression (STAT-033) is a filter rather than a join,
  # and so adding a family never requires a schema change.
  class ContextValue < ApplicationRecord
    self.table_name = "context_values"

    belongs_to :organization
    belongs_to :context, class_name: "Analysis::Context", inverse_of: :context_values
    belongs_to :evidence_set, optional: true

    validates :dimension_key, :dimension_version, presence: true
    validates :quality_state, inclusion: { in: Observation::QUALITY_STATES }

    def readonly? = persisted?

    def observed? = quality_state == "observed"

    # STAT-002 at the analytical layer: a dimension that could not be computed
    # has no value, not a zero.
    def value
      return nil unless observed?

      value_numeric || value_text || value_boolean || value_json
    end

    # STAT-033: two values in the same semantic family are not independent
    # confirmation of each other.
    def same_family_as?(other)
      semantic_family.present? && semantic_family == other.semantic_family
    end
  end
end
