# frozen_string_literal: true

# Epic 001-02. Invitation-based organization membership (HO §11 v0.1).
#
# Not in the HO §167 draft schema inventory — added because §11 requires
# invitation-based membership and the inventory does not name a table for it.
# Recorded in the epic Decision Log.
#
# Only a digest of the token is stored. The raw token exists in the invitation
# email and nowhere else, so a database disclosure does not let an attacker
# accept outstanding invitations. Same reasoning as HO §108 on hashed
# integration credentials.
class CreateInvitations < ActiveRecord::Migration[8.1]
  ROLES = %w[organization_admin clinical_ops clinician analyst support_limited].freeze

  def change
    create_table :invitations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.text :email_address, null: false
      t.text :role, null: false
      t.text :token_digest, null: false
      t.references :invited_by, null: false, type: :uuid,
        foreign_key: { to_table: :users }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :accepted_by, type: :uuid,
        foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true

    # At most one outstanding invitation per email per organization. Partial,
    # so a fresh invitation can be issued after a previous one is accepted.
    add_index :invitations, [ :organization_id, :email_address ],
      unique: true,
      where: "accepted_at IS NULL",
      name: "index_invitations_on_org_and_email_outstanding"

    add_check_constraint :invitations,
      "role IN (#{ROLES.map { |r| "'#{r}'" }.join(', ')})",
      name: "invitations_role_check"
  end
end
