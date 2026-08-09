# frozen_string_literal: true

# Invitation-based organization membership (HO §11 v0.1).
#
# Only a digest of the token is persisted. The raw token exists in the
# invitation email and nowhere else, so a database disclosure does not let an
# attacker accept outstanding invitations — the same reasoning HO §108 applies
# to integration credentials.
class Invitation < ApplicationRecord
  DEFAULT_VALIDITY = 7.days

  belongs_to :organization
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  validates :email_address, presence: true
  validates :role, inclusion: { in: OrganizationMembership::ROLES }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  scope :outstanding, -> { where(accepted_at: nil).where(expires_at: Time.current..) }

  # Returns [invitation, raw_token]. The raw token is returned once and never
  # recoverable afterwards.
  def self.issue!(organization:, email_address:, role:, invited_by:, validity: DEFAULT_VALIDITY)
    raw = SecureRandom.urlsafe_base64(32)

    invitation = create!(
      organization: organization,
      email_address: email_address,
      role: role,
      invited_by: invited_by,
      token_digest: digest(raw),
      expires_at: validity.from_now
    )

    [ invitation, raw ]
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def self.find_outstanding_by_token(raw)
    return nil if raw.blank?

    outstanding.find_by(token_digest: digest(raw))
  end

  def expired? = expires_at.past?
  def accepted? = accepted_at.present?

  # Accepting creates the membership and marks the invitation in one
  # transaction, so a crash cannot leave a consumed token without access or a
  # membership without a record of how it was granted.
  def accept!(user)
    raise ArgumentError, "invitation already accepted" if accepted?
    raise ArgumentError, "invitation expired" if expired?

    transaction do
      membership = OrganizationMembership.create!(
        organization: organization,
        user: user,
        role: role,
        status: "active",
        invited_at: created_at,
        joined_at: Time.current
      )

      update!(accepted_at: Time.current, accepted_by: user)
      membership
    end
  end
end
