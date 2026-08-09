# frozen_string_literal: true

# Binds a User to an Organization with a role (HO §10.2). This is the object
# authorization consults — never the User.
#
# HO §11: "Do not overbuild fine-grained permission matrices initially."
# A single role, with policy objects interpreting it.
class OrganizationMembership < ApplicationRecord
  ROLES = %w[organization_admin clinical_ops clinician analyst support_limited].freeze
  STATUSES = %w[invited active suspended].freeze

  belongs_to :organization
  belongs_to :user
  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :organization_id }

  scope :active, -> { where(status: "active") }

  def active? = status == "active"
  def organization_admin? = role == "organization_admin"

  # Roles permitted to read subject health data. support_limited is
  # deliberately excluded: HO §157 wants audited support access, not blanket
  # visibility of health data.
  CLINICAL_ROLES = %w[organization_admin clinical_ops clinician analyst].freeze

  def clinical_access? = CLINICAL_ROLES.include?(role)
end
