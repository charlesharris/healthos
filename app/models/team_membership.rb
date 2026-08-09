# frozen_string_literal: true

# Joins a Team to an OrganizationMembership rather than directly to a User, so
# a team member is necessarily an organization member and their role travels
# with them.
class TeamMembership < ApplicationRecord
  belongs_to :organization
  belongs_to :team
  belongs_to :organization_membership

  validates :organization_membership_id, uniqueness: { scope: :team_id }

  validate :team_and_membership_share_organization

  private

  # Defence in depth against building a cross-tenant team. The database
  # cannot express this with a plain foreign key, so it is asserted here and
  # covered by a spec.
  def team_and_membership_share_organization
    return if team.blank? || organization_membership.blank?

    unless team.organization_id == organization_membership.organization_id
      errors.add(:base, "team and membership must belong to the same organization")
    end

    unless organization_id == team.organization_id
      errors.add(:organization_id, "must match the team's organization")
    end
  end
end
