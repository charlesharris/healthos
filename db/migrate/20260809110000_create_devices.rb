# frozen_string_literal: true

# Epic 001-07. HO §20. Schema only — exercised in epic 002 (002-05 derives
# source and recording-method changes from these transitions).
#
# "Device/source transitions must be queryable" (HO §20). That is not a
# convenience: STAT-007 evaluates instrumentation before biology, and
# STAT-008/009 cap or suppress biological evidence when the source changed
# mid-window. Answering "what was recording on this date" is therefore a
# statistical requirement, which is why active_from/active_to are columns
# rather than something inferred from observation history.
class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, foreign_key: true, type: :uuid
      t.references :source, null: false, foreign_key: true, type: :uuid

      t.text :external_id, null: false
      t.text :manufacturer
      t.text :model
      t.text :device_type
      t.text :firmware_version

      t.datetime :active_from, null: false
      t.datetime :active_to

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :devices, [ :organization_id, :source_id, :external_id ], unique: true,
      name: "index_devices_identity"
    # The transition query: which devices were active for this subject over a
    # window. Partial on active_to so the common "currently active" lookup
    # stays cheap.
    add_index :devices, [ :organization_id, :subject_id, :active_from ],
      name: "index_devices_on_org_subject_active_from"
  end
end
