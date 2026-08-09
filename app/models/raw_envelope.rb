# frozen_string_literal: true

# Raw source truth, preserved before transformation (HO §13.1, INV-1).
#
# Append-only, and enforced rather than promised: the app role holds SELECT
# and INSERT only (ADR-002 4a) and the payload sits in an object-locked bucket
# (4b). `readonly?` below is the fast, legible error in front of the database's
# refusal — belt and braces, neither of them a trigger.
class RawEnvelope < ApplicationRecord
  belongs_to :organization
  belongs_to :source
  belongs_to :subject, optional: true

  validates :source_record_id, :content_type, :object_key, :content_hash,
    :received_at, :adapter_key, :adapter_version, presence: true
  validates :public_id, presence: true, uniqueness: { scope: :organization_id }

  before_validation :assign_public_id, on: :create

  scope :for_source, ->(source) { where(source_id: source.id) }

  # Mutating raw evidence is never legitimate. Late or corrected data arrives
  # as a NEW envelope with a new source_record_version (HO §155).
  def readonly?
    persisted?
  end

  # Reads the payload back and verifies its hash (ADR-002 4b). Every
  # provenance drilldown goes through here, so altered evidence surfaces as an
  # error rather than as plausible-looking bytes.
  def payload(store: Storage::RawPayloadStore.instance)
    store.read(object_key: object_key, expected_hash: content_hash)
  end

  private

  def assign_public_id
    self.public_id ||= "env_#{SecureRandom.alphanumeric(20).downcase}"
  end
end
