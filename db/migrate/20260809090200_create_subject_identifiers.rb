# frozen_string_literal: true

# Epic 001-04. HO §10.3: external identifiers — FHIR Patient ID, MRN, RPM
# platform member ID, device platform member ID.
#
# "Unique constraints are scoped by organization + system" (HO §10.3): the same
# MRN may legitimately exist in two organizations and must not collide.
class CreateSubjectIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :subject_identifiers, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :system, null: false
      t.text :value, null: false
      t.references :source, type: :uuid, index: false

      t.timestamps
    end

    # S2C-022. This is what makes identity resolution idempotent: resolving the
    # same (system, value) twice cannot produce two subjects, and the guarantee
    # is the database's rather than the service layer's.
    add_index :subject_identifiers, [ :organization_id, :system, :value ],
      unique: true, name: "index_subject_identifiers_unique_per_org"

    add_index :subject_identifiers, [ :organization_id, :subject_id ],
      name: "index_subject_identifiers_on_org_and_subject"
  end
end
