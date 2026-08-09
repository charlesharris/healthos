# frozen_string_literal: true

# One input within an EvidenceSet (HO §22).
#
# Polymorphic by design, and knowingly so: HO §22 accepts weaker relational
# enforcement in exchange for one consistent drilldown across every artifact
# type. HO §169 keeps that trade open for review.
class EvidenceItem < ApplicationRecord
  # Only canonical evidence may be referenced. A free-form polymorphic column
  # would otherwise let anything in, and "drill down to source records"
  # (INV-4) would stop meaning anything specific.
  ALLOWED_RECORD_TYPES = %w[
    Observation ObservationGroup Event Interval DerivedSignal RawEnvelope
  ].freeze

  belongs_to :evidence_set
  belongs_to :organization

  validates :record_type, inclusion: { in: ALLOWED_RECORD_TYPES }
  validates :record_id, presence: true

  def readonly? = persisted?

  def resolve
    record_type.constantize.find_by(id: record_id)
  end
end
