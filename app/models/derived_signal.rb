# frozen_string_literal: true

# A canonical reproducible calculation (HO §26).
#
# Append-only. HO §26: "do not overwrite a derived signal used by a pinned
# Investigation." Rather than tracking which signals are pinned, none are ever
# overwritten — recomputation under a new algorithm version creates a new row
# and the old one is marked superseded (HO §155).
class DerivedSignal < ApplicationRecord
  STATUSES = %w[computed insufficient_input superseded failed].freeze

  belongs_to :organization
  belongs_to :subject
  belongs_to :evidence_set, optional: true

  validates :semantic_key, :semantic_version, :window_started_at, :window_ended_at,
    :algorithm_key, :algorithm_version, :algorithm_digest, :computed_at, :as_of,
    presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :computed, -> { where(status: "computed") }
  scope :for_key, ->(key) { where(semantic_key: key) }
  scope :in_window, ->(from, to) { where(window_started_at: from..to) }

  def readonly? = persisted?

  def computed? = status == "computed"

  # STAT-021 / ADR-001 §5b: the denominator travels with the value. A
  # derived value that cannot state how many usable inputs it had is not
  # interpretable, and recomputing the count later answers a different
  # question than the one the value was computed under.
  def denominator = { usable: usable_input_count, raw: raw_input_count }

  # INV-3: exact lineage, resolving to the precise input records.
  def inputs
    evidence_set ? evidence_set.resolve : []
  end

  def algorithm = "#{algorithm_key}@v#{algorithm_version}"
end
