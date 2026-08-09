# frozen_string_literal: true

# A person who can sign in. Users are global, not tenant-scoped: HO §10.2
# anticipates that "a user may eventually belong to multiple organizations".
#
# There is deliberately no `role` here. HO §10.2: "Do not put one global role
# field directly on User." Role and status per tenant live on
# OrganizationMembership, which is what authorization consults.
class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: %w[active disabled] }

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  # Memberships this user can actually act through. A suspended membership or
  # a disabled user grants nothing, which is why authorization asks here
  # rather than checking the user alone.
  def usable_memberships
    return OrganizationMembership.none unless active?

    organization_memberships.active
  end

  def membership_for(organization)
    return nil if organization.blank?

    usable_memberships.find_by(organization_id: organization.id)
  end
end
