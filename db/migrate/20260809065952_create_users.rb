# frozen_string_literal: true

# Epic 001-02.
#
# Users are global, not tenant-scoped: HO §10.2 says "a user may eventually
# belong to multiple organizations", so there is deliberately no
# organization_id here. Tenancy lives on organization_memberships.
#
# There is also deliberately no `role` column. HO §10.2: "Do not put one
# global role field directly on User." Role belongs to the membership.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :full_name
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :users, :email_address, unique: true

    add_check_constraint :users,
      "status IN ('active', 'disabled')",
      name: "users_status_check"
  end
end
