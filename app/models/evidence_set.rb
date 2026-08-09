# frozen_string_literal: true

# The generic drilldown mechanism (HO §22). Append-only: an evidence set
# records what a calculation actually consumed, so editing it would rewrite
# history (INV-3).
class EvidenceSet < ApplicationRecord
  PURPOSES = %w[
    derived_signal_inputs context_inputs baseline_inputs
    comparison_affected_inputs comparison_baseline_inputs investigation_snapshot
  ].freeze

  belongs_to :organization
  has_many :evidence_items, -> { order(:ordinal) }, dependent: :restrict_with_error, inverse_of: :evidence_set

  validates :purpose, inclusion: { in: PURPOSES }
  validates :as_of, :fingerprint, presence: true

  def readonly? = persisted?

  # Deterministic over the ordered input identities. Two sets over the same
  # inputs share a fingerprint, which is how a recomputation recognises it
  # would produce an identical result (HO §26).
  def self.fingerprint_for(records)
    material = records.map { |r| "#{r.class.name}:#{r.id}" }.sort
    Digest::SHA256.hexdigest(material.join("|"))
  end

  # Records the exact inputs a calculation consumed.
  def self.record!(organization:, purpose:, as_of:, records:, role: "input")
    set = create!(
      organization: organization, purpose: purpose, as_of: as_of,
      fingerprint: fingerprint_for(records)
    )

    records.each_with_index do |record, index|
      EvidenceItem.create!(
        evidence_set: set, organization: organization,
        record_type: record.class.name, record_id: record.id,
        role: role, ordinal: index
      )
    end

    set
  end

  # Resolves back to the actual records. This is what INV-4's "every Finding
  # can be drilled into" ultimately calls.
  def resolve
    evidence_items.map(&:resolve)
  end
end
