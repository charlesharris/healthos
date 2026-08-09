# frozen_string_literal: true

# Epic 001-07. HO §17.
#
# "Preserves joint-measurement semantics without requiring compound JSON
# values." A BP reading is systolic + diastolic + pulse taken together; the
# group is what makes them one measurement rather than three coincidences.
# That matters statistically — SC §5 requires an explicit analytical unit, and
# three observations from one cuff inflation are one unit, not three
# (STAT-005).
class CreateObservationGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :observation_groups, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      t.datetime :observed_at, null: false

      t.references :source, null: false, foreign_key: true, type: :uuid
      t.references :raw_envelope, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :observation_groups, [ :organization_id, :subject_id, :observed_at ],
      name: "index_observation_groups_on_org_subject_time"
  end
end
