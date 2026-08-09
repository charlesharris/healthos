# frozen_string_literal: true

# Epic 001-02. Teams exist so Cases can be routed to a group rather than an
# individual (HO §44 case routing, landing in epic 002).
class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.text :name, null: false
      t.text :status, null: false, default: "active"

      t.timestamps
    end

    add_index :teams, [ :organization_id, :name ], unique: true

    add_check_constraint :teams,
      "status IN ('active', 'archived')",
      name: "teams_status_check"
  end

  # team_memberships joins a team to an organization_membership rather than
  # directly to a user, so a team member is necessarily an organization member
  # and their role travels with them.
  #
  # organization_id is denormalized here on purpose. HO §10.1: "Every
  # high-risk operational/health table should carry organization_id directly
  # even if derivable through another association" — for tenant-safe indexes,
  # simpler audit queries, and future RLS.
end
