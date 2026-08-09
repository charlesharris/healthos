# frozen_string_literal: true

# Platform-level administrative access — the actor HO §157's "provider-safe
# internal tools" implies but never names.
#
# Distinct from OrganizationMembership: that is a role within one tenant,
# this is access across all of them. Every action taken through it is written
# to audit_events (HO §92 "Admin configuration changed", HO §157 "support
# access must itself be audited").
class StaffMember < ApplicationRecord
  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true

  validates :status, inclusion: { in: %w[active revoked] }
  validates :user_id, uniqueness: true

  before_validation :set_granted_at, on: :create

  scope :active, -> { where(status: "active") }

  def active? = status == "active" && revoked_at.nil?

  def self.for(user)
    return nil if user.blank?

    active.find_by(user_id: user.id)
  end

  private

  def set_granted_at
    self.granted_at ||= Time.current
  end
end
