# frozen_string_literal: true

# Where evidence came from (HO §13.2).
class Source < ApplicationRecord
  SOURCE_TYPES = %w[synthetic csv_import customer_api fhir device_cloud rpm_vendor manual].freeze
  STATUSES = %w[active paused disabled].freeze

  belongs_to :organization
  has_many :raw_envelopes, dependent: :restrict_with_error

  # HO §13.2: "Do not put credentials in ordinary JSON columns."
  encrypts :configuration_encrypted

  validates :key, presence: true, uniqueness: { scope: :organization_id }
  validates :display_name, presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def active? = status == "active"

  def configuration
    raw = configuration_encrypted
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def configuration=(hash)
    self.configuration_encrypted = hash.to_json
  end

  # Source health, surfaced by the admin view in 005-07. Recorded as separate
  # timestamps rather than a single status so an intermittently failing source
  # is distinguishable from a dead one.
  def record_success!(at: Time.current)
    update!(last_success_at: at, last_failure_reason: nil)
  end

  def record_failure!(reason:, at: Time.current)
    update!(last_failure_at: at, last_failure_reason: reason.to_s.truncate(500))
  end
end
