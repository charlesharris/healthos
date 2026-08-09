# frozen_string_literal: true

# Epic 001-02.
class CreateTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :team_memberships, id: :uuid, default: -> { "uuidv7()" } do |t|
      # Denormalized per HO §10.1 even though it is reachable via team.
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :team, null: false, foreign_key: true, type: :uuid
      # Joined to the membership, not the user, so a team member is
      # necessarily an organization member and their role travels with them.
      t.references :organization_membership, null: false, foreign_key: true, type: :uuid,
        index: { name: "index_team_memberships_on_org_membership_id" }

      t.timestamps
    end

    add_index :team_memberships, [ :team_id, :organization_membership_id ],
      unique: true, name: "index_team_memberships_on_team_and_membership"

    add_index :team_memberships, [ :organization_id, :team_id ],
      name: "index_team_memberships_on_org_and_team"
  end
end
