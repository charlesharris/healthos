# frozen_string_literal: true

# Epic 001-07. HO §18 (Event), §19 (Interval).
#
# Schema only — the epic defers exercising these to epic 002. Created now so
# the canonical telemetry model is complete and later migrations do not have
# to interleave with analysis work.
#
# Events are point-in-time facts (medication ordered, visit occurred, device
# changed). Intervals are spans (hospitalization, sleep session, treatment
# cycle). Both are canonical telemetry alongside observations, and both are
# append-only (INV-2).
class CreateEventsAndIntervals < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      t.datetime :occurred_at, null: false
      t.datetime :ended_at

      t.references :source, null: false, foreign_key: true, type: :uuid
      t.references :device, foreign_key: true, type: :uuid
      t.references :raw_envelope, null: false, foreign_key: true, type: :uuid

      t.text :recording_method, null: false, default: "unknown"
      t.jsonb :attributes_json, null: false, default: {}

      t.text :normalizer_key, null: false
      t.integer :normalizer_version, null: false

      t.timestamps
    end

    add_index :events, [ :organization_id, :public_id ], unique: true
    add_index :events, [ :organization_id, :subject_id, :semantic_key, :occurred_at ],
      order: { occurred_at: :desc }, name: "index_events_on_org_subject_key_time"

    create_table :intervals, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      t.datetime :started_at, null: false
      # Nullable: an interval may be open, which is materially different from
      # one that ended at an unknown time.
      t.datetime :ended_at

      t.references :source, null: false, foreign_key: true, type: :uuid
      t.references :raw_envelope, null: false, foreign_key: true, type: :uuid

      t.jsonb :attributes_json, null: false, default: {}

      t.text :normalizer_key, null: false
      t.integer :normalizer_version, null: false

      t.timestamps
    end

    add_index :intervals, [ :organization_id, :public_id ], unique: true
    add_index :intervals, [ :organization_id, :subject_id, :semantic_key, :started_at ],
      order: { started_at: :desc }, name: "index_intervals_on_org_subject_key_time"

    add_check_constraint :intervals,
      "ended_at IS NULL OR ended_at >= started_at",
      name: "intervals_end_after_start_check"
  end
end
