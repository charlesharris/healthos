# frozen_string_literal: true

# Platform-level (not tenant-level) administrative access.
#
# DEVIATION: the governing documents describe no system-administrator concept.
# HO §11's roles — including support_limited — are OrganizationMembership
# roles, scoped to a single tenant. HO §157 requires "provider-safe internal
# tools" and says "support access must itself be audited", but never says who
# may use them. This table introduces that missing actor.
#
# A separate table rather than a flag on users: CLAUDE.md forbids a global
# role field on User, and while a boolean is not literally a role, a table
# respects the intent and records who granted access and when.
#
# Deliberately NOT tenant-scoped. Staff see across organizations, which is a
# narrow audited exception to INV-31 — hence every staff action is written to
# audit_events.
class CreateStaffMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_members, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.text :status, null: false, default: "active"
      t.datetime :granted_at, null: false
      t.references :granted_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :revoked_at
      t.text :note

      t.timestamps
    end

    add_check_constraint :staff_members,
      "status IN ('active', 'revoked')",
      name: "staff_members_status_check"
  end
end
