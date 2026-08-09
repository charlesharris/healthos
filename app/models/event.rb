# frozen_string_literal: true

# A point-in-time canonical fact (HO §18): medication ordered, visit occurred,
# device changed, PT session completed. Append-only (INV-2).
#
# Schema landed in 001-07; exercised in epic 002.
class Event < ApplicationRecord
  self.table_name = "events"

  belongs_to :organization
  belongs_to :subject
  belongs_to :source
  belongs_to :raw_envelope
  belongs_to :device, optional: true

  validates :semantic_key, :semantic_version, :occurred_at,
    :normalizer_key, :normalizer_version, presence: true
  validates :public_id, presence: true, uniqueness: { scope: :organization_id }

  before_validation { self.public_id ||= "evt_#{SecureRandom.alphanumeric(20).downcase}" }

  def readonly? = persisted?
end
