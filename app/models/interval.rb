# frozen_string_literal: true

# A canonical span (HO §19): hospitalization, sleep session, treatment cycle,
# travel period, recovery phase. Append-only (INV-2).
#
# Schema landed in 001-07; exercised in epic 002.
class Interval < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  belongs_to :source
  belongs_to :raw_envelope

  validates :semantic_key, :semantic_version, :started_at,
    :normalizer_key, :normalizer_version, presence: true
  validates :public_id, presence: true, uniqueness: { scope: :organization_id }

  before_validation { self.public_id ||= "int_#{SecureRandom.alphanumeric(20).downcase}" }

  # An open interval is materially different from one that ended at an unknown
  # time, so nil ended_at means "still open", never "unknown".
  def open? = ended_at.nil?

  def readonly? = persisted?
end
