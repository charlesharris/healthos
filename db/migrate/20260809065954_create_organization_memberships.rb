# frozen_string_literal: true

# Epic 001-02.
#
# The membership owns organization, role, and status (HO §10.2). This is the
# join that makes tenancy real: authorization asks the membership, never the
# user.
#
# Roles are the HO §11 v0.1 list. "Do not overbuild fine-grained permission
# matrices initially" — a single role column, not a permission matrix.
class CreateOrganizationMemberships < ActiveRecord::Migration[8.1]
  ROLES = %w[organization_admin clinical_ops clinician analyst support_limited].freeze
  STATUSES = %w[invited active suspended].freeze

  def change
    create_table :organization_memberships, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :role, null: false
      t.text :status, null: false, default: "active"
      t.datetime :invited_at
      t.datetime :joined_at

      t.timestamps
    end

    # S2C-022: critical uniqueness belongs in PostgreSQL, not only in Ruby.
    # One membership per user per organization.
    add_index :organization_memberships, [ :organization_id, :user_id ],
      unique: true, name: "index_org_memberships_on_org_and_user"

    # Tenant-prefixed (HO §12): every lookup starts from the organization.
    add_index :organization_memberships, [ :organization_id, :role ],
      name: "index_org_memberships_on_org_and_role"

    add_check_constraint :organization_memberships,
      "role IN (#{ROLES.map { |r| "'#{r}'" }.join(', ')})",
      name: "organization_memberships_role_check"

    add_check_constraint :organization_memberships,
      "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(', ')})",
      name: "organization_memberships_status_check"
  end
end
