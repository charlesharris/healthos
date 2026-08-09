# frozen_string_literal: true

# The tenant root (HO §10.1). Every high-risk operational or health table
# carries organization_id directly, even where it is derivable through an
# association — for tenant-safe indexes, simple audit queries, defence in
# depth, and future RLS.
class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :teams, dependent: :destroy
  has_many :invitations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase alphanumeric with hyphens" }
  validates :status, inclusion: { in: %w[active suspended] }

  scope :active, -> { where(status: "active") }

  def active? = status == "active"
end
