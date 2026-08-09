# frozen_string_literal: true

# Epic 001-10. HO §31 (configuration), §32 (evaluation), §33–34 (Signal).
#
# S2C-003 is the architectural line this whole layer exists to hold: a Monitor
# may create a Signal, never a Case. Machine evidence and human work are
# separate concerns, and collapsing them is what turns an observability
# product back into an alert manager.
class CreateMonitoringTables < ActiveRecord::Migration[8.1]
  SEVERITIES = %w[info low moderate high].freeze

  def change
    # HO §31: monitor DEFINITION (code, versioned) is separate from
    # organization CONFIGURATION (data). "This lets customer policy specify
    # thresholds without changing code definition identity" — and it keeps
    # HO §31's rule that "clinical threshold defaults should not be invented
    # by platform core" enforceable, since core ships no parameters at all.
    create_table :monitor_configurations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.text :domain_key, null: false
      t.text :monitor_key, null: false
      t.integer :monitor_version, null: false

      t.boolean :enabled, null: false, default: true
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :routing_parameters, null: false, default: {}

      t.timestamps
    end

    add_index :monitor_configurations,
      [ :organization_id, :monitor_key, :monitor_version ],
      unique: true, name: "index_monitor_configurations_identity"
    add_index :monitor_configurations, [ :organization_id, :domain_key, :enabled ],
      name: "index_monitor_configurations_on_org_domain_enabled"

    # HO §32: "useful for debugging — why did a Signal exist, or not exist?"
    # A monitor that declines to fire is as interesting as one that fires,
    # and without this the negative case leaves no trace at all.
    create_table :monitor_evaluations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :monitor_key, null: false
      t.integer :monitor_version, null: false

      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false
      t.datetime :evaluated_at, null: false

      t.text :result, null: false
      # Digest of the inputs considered. Two evaluations over identical inputs
      # share a fingerprint, which is what makes "why did this not fire again"
      # answerable.
      t.text :input_fingerprint
      t.jsonb :details, null: false, default: {}

      t.references :signal, type: :uuid, index: false

      t.timestamps
    end

    add_index :monitor_evaluations,
      [ :organization_id, :subject_id, :monitor_key, :evaluated_at ],
      order: { evaluated_at: :desc }, name: "index_monitor_evaluations_lookup"

    add_check_constraint :monitor_evaluations,
      "result IN ('triggered', 'not_triggered', 'insufficient_data', 'skipped', 'error')",
      name: "monitor_evaluations_result_check"

    # HO §33. Immutable machine evidence (S2C-001).
    create_table :signals, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :monitor_key, null: false
      t.integer :monitor_version, null: false
      t.text :monitor_digest, null: false

      t.text :signal_type, null: false
      t.text :domain_key, null: false

      t.datetime :detected_at, null: false
      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at

      t.text :severity, null: false, default: "info"
      t.jsonb :attributes_json, null: false, default: {}

      t.text :source_record_type
      t.uuid :source_record_id

      # HO §34: derived from organization, subject, monitor key/version,
      # evaluation window and semantic event identity.
      t.text :deduplication_key, null: false

      t.timestamps
    end

    # S2C-002 / HO §110. The authority for "a monitor job may run repeatedly;
    # the second execution returns the existing Signal". A service-layer check
    # would lose the race under concurrent evaluation, which is exactly what
    # S2C-022 says to put in the database instead.
    add_index :signals, [ :organization_id, :deduplication_key ], unique: true,
      name: "index_signals_on_org_and_dedupe_key"
    add_index :signals, [ :organization_id, :public_id ], unique: true
    add_index :signals, [ :organization_id, :subject_id, :domain_key, :detected_at ],
      order: { detected_at: :desc }, name: "index_signals_on_org_subject_domain_time"

    add_check_constraint :signals,
      "severity IN (#{SEVERITIES.map { |s| "'#{s}'" }.join(', ')})",
      name: "signals_severity_check"

    add_foreign_key :monitor_evaluations, :signals
  end
end
