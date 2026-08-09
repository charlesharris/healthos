# frozen_string_literal: true

# A routing target for Cases (HO §44), landing in epic 002.
class Team < ApplicationRecord
  belongs_to :organization
  has_many :team_memberships, dependent: :destroy
  has_many :organization_memberships, through: :team_memberships

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: %w[active archived] }

  scope :active, -> { where(status: "active") }
end
