# frozen_string_literal: true

# Epic 001-05. HO §13.2.
#
# A Source is where evidence came from: a FHIR endpoint, RPM vendor, device
# cloud, CSV import, customer API, or manual admin import.
class CreateSources < ActiveRecord::Migration[8.1]
  SOURCE_TYPES = %w[
    synthetic csv_import customer_api fhir device_cloud rpm_vendor manual
  ].freeze

  def change
    create_table :sources, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.text :key, null: false
      t.text :source_type, null: false
      t.text :display_name, null: false
      t.text :status, null: false, default: "active"

      # HO §13.2: "Do not put credentials in ordinary JSON columns."
      # Application-level encryption, and named _encrypted so a plain-JSON
      # column cannot be introduced later without the rename being obvious.
      t.text :configuration_encrypted

      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.text :last_failure_reason

      t.timestamps
    end

    add_index :sources, [ :organization_id, :key ], unique: true
    add_index :sources, [ :organization_id, :status ]

    add_check_constraint :sources,
      "status IN ('active', 'paused', 'disabled')",
      name: "sources_status_check"

    add_check_constraint :sources,
      "source_type IN (#{SOURCE_TYPES.map { |s| "'#{s}'" }.join(', ')})",
      name: "sources_source_type_check"
  end
end
