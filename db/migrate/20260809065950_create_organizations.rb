# frozen_string_literal: true

# Epic 001-02. Organization is the tenant root (HO §10.1).
class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :organizations, :slug, unique: true

    # HO §112: "CHECK enum values where appropriate". Rails validations
    # improve UX; database constraints protect correctness.
    add_check_constraint :organizations,
      "status IN ('active', 'suspended')",
      name: "organizations_status_check"
  end
end
