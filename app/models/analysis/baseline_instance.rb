# frozen_string_literal: true

module Analysis
  # A materialized baseline (HO §57, SC §19-22).
  #
  # Maturity is stored and shown (STAT-015) because a comparison against an
  # immature baseline is a materially weaker claim than one against a mature
  # baseline, and the reader must be able to tell which they are looking at.
  # Immutable, like every analytical artifact.
  class BaselineInstance < ApplicationRecord
    MATURITIES = %w[immature partial mature].freeze

    belongs_to :organization
    belongs_to :subject
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id,
      optional: true, inverse_of: false
    belongs_to :evidence_set, optional: true

    validates :definition_key, :definition_version, :definition_digest, :baseline_type,
      :window_started_at, :window_ended_at, :as_of, :fingerprint, presence: true
    validates :maturity, inclusion: { in: MATURITIES }

    def readonly? = persisted?

    def mature? = maturity == "mature"
    def immature? = maturity == "immature"

    # SC §21 requires all four to travel together — a baseline that cannot
    # state its own span and completeness cannot be judged.
    def summary
      { usable_units: usable_units, calendar_span_days: calendar_span_days,
        completeness: completeness, maturity: maturity }
    end

    def inputs = evidence_set ? evidence_set.resolve : []
  end
end
