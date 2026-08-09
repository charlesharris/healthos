# frozen_string_literal: true

# Epic 001-04. HO §10.3.
#
# "Subject", never "Patient" (INV-35, CLAUDE.md vocabulary): domain-neutral,
# avoids implying the system owns the complete clinical Patient concept, and
# maps cleanly to external Patient/member/person identifiers.
class CreateSubjects < ActiveRecord::Migration[8.1]
  def change
    create_table :subjects, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      # Non-sequential external handle. Internal UUIDs are UUIDv7 and therefore
      # encode a creation timestamp; public_id is random so URLs and exports
      # leak neither ordering nor enrolment time (HO §123 ID enumeration).
      t.text :public_id, null: false

      t.text :status, null: false, default: "active"

      # Subject-local time. HO §121 lists timezone boundaries as a required
      # statistical regression case, and completeness denominators are
      # day-based (SC §13–14), so "which day" must be answerable in the
      # subject's own timezone rather than the server's.
      t.text :timezone, null: false, default: "UTC"

      t.timestamps
    end

    add_index :subjects, [ :organization_id, :public_id ], unique: true
    add_index :subjects, [ :organization_id, :status ]

    add_check_constraint :subjects,
      "status IN ('active', 'inactive', 'archived')",
      name: "subjects_status_check"
  end
end
