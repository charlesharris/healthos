# frozen_string_literal: true

# A joint measurement (HO §17): systolic + diastolic + pulse from one cuff
# inflation, a lab panel, a body-composition reading.
#
# Statistically load-bearing. SC §5 requires an explicit analytical unit and
# STAT-005 forbids inflating n through repeated readings — three observations
# from one inflation are one analytical unit, and the group is what records
# that.
class ObservationGroup < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  belongs_to :source
  belongs_to :raw_envelope
  has_many :observations, dependent: :restrict_with_error

  validates :semantic_key, :semantic_version, :observed_at, presence: true

  def readonly?
    persisted?
  end
end
