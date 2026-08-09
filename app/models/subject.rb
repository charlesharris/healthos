# frozen_string_literal: true

# The core platform entity (HO §10.3). Subject, never Patient (INV-35).
#
# Carries no PHI itself — identity lives in SubjectIdentity so that telemetry,
# monitoring and analysis can join against subjects freely without touching
# protected data.
class Subject < ApplicationRecord
  STATUSES = %w[active inactive archived].freeze

  belongs_to :organization
  has_one :subject_identity, dependent: :destroy
  has_many :subject_identifiers, dependent: :destroy

  validates :public_id, presence: true, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }
  validates :timezone, presence: true
  validate :timezone_must_be_recognized

  before_validation :assign_public_id, on: :create

  scope :active, -> { where(status: "active") }

  def active? = status == "active"

  # Subject-local day boundary. Completeness denominators are day-based
  # (SC §13–14) and HO §121 requires timezone boundaries to be a tested
  # regression case, so "which day did this reading belong to" is answered
  # here rather than with the server's zone.
  def local_date(time)
    time.in_time_zone(timezone).to_date
  end

  private

  def assign_public_id
    # Random rather than derived: internal ids are UUIDv7 and encode creation
    # time, which a public handle should not disclose.
    self.public_id ||= "sub_#{SecureRandom.alphanumeric(20).downcase}"
  end

  def timezone_must_be_recognized
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?

    errors.add(:timezone, "is not a recognized timezone")
  end
end
