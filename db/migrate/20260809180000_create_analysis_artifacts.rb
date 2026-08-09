# frozen_string_literal: true

# Epic 003-03, 003-07. HO §52 (Context), §53 (ContextValue), §57
# (BaselineInstance).
#
# INV-13/14 and HO §50: completed analytical artifacts are IMMUTABLE
# snapshots. Late data does not rewrite them — it marks the Case analysis
# stale and produces NEW artifacts, and the Case's current_* pointers move
# (HO §99). Saved Investigations keep referencing the old ones, which is what
# makes STAT-040/041 possible.
class CreateAnalysisArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contexts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid
      t.references :case, foreign_key: true, type: :uuid

      # INV-9: Context definitions are versioned, and the digest catches a
      # behaviour change made without a version bump (HO §25).
      t.text :definition_key, null: false
      t.integer :definition_version, null: false
      t.text :definition_digest, null: false

      t.text :anchor_type, null: false
      t.uuid :anchor_id

      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false
      t.datetime :as_of, null: false

      t.text :status, null: false, default: "materialized"
      t.decimal :data_completeness
      t.references :input_evidence_set, type: :uuid, foreign_key: { to_table: :evidence_sets }

      # HO §80: the full reproducibility tuple, so an artifact can state every
      # version it was computed under without a join.
      t.jsonb :version_tuple, null: false, default: {}
      t.text :fingerprint, null: false

      t.timestamps
    end

    add_index :contexts, [ :organization_id, :subject_id, :as_of ],
      name: "index_contexts_on_org_subject_as_of"
    # HO §26-style identity: the same definition over the same inputs at the
    # same instant is the same Context, so a retried materialization returns
    # rather than duplicates.
    add_index :contexts,
      [ :organization_id, :subject_id, :definition_key, :definition_version, :as_of, :fingerprint ],
      unique: true, name: "index_contexts_identity"

    add_check_constraint :contexts,
      "status IN ('materialized', 'insufficient_input', 'failed')",
      name: "contexts_status_check"

    # HO §53: typed row-per-dimension. Physically not a wide Honeycomb row;
    # the Context stays logically wide, and ADR-001 §6 records that the JSONB
    # projection is deferred until the T1/T3 tripwires fire rather than built
    # speculatively.
    create_table :context_values, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :context, null: false, foreign_key: true, type: :uuid

      t.text :dimension_key, null: false
      t.integer :dimension_version, null: false

      t.decimal :value_numeric
      t.text :value_text
      t.boolean :value_boolean
      t.jsonb :value_json
      t.text :unit

      t.datetime :window_started_at
      t.datetime :window_ended_at

      # STAT-010: the missingness taxonomy survives into the analytical layer.
      # A dimension that could not be computed is not a dimension with a zero.
      t.text :quality_state, null: false, default: "observed"

      # SC §49-50 difference families, carried on every value so
      # correlated-family suppression (STAT-033) never needs a join or a
      # schema change.
      t.text :source_family
      t.text :semantic_family
      t.text :derivation_family

      t.references :evidence_set, type: :uuid, foreign_key: true

      t.timestamps
    end

    add_index :context_values, [ :context_id, :dimension_key ], unique: true,
      name: "index_context_values_unique_per_context"
    add_index :context_values, [ :organization_id, :dimension_key ],
      name: "index_context_values_on_org_and_dimension"

    # Same value-representation rule as observations and derived signals: a
    # dimension that is not `observed` carries no value. STAT-002 enforced at
    # every layer rather than assumed to hold downstream.
    add_check_constraint :context_values, <<~SQL.squish, name: "context_values_value_representation_check"
      quality_state = 'observed'
      OR (value_numeric IS NULL AND value_text IS NULL
          AND value_boolean IS NULL AND value_json IS NULL)
    SQL

    create_table :baseline_instances, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid
      t.references :case, foreign_key: true, type: :uuid

      t.text :definition_key, null: false
      t.integer :definition_version, null: false
      t.text :definition_digest, null: false

      t.text :baseline_type, null: false

      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false
      t.datetime :as_of, null: false

      # SC §21: a baseline stores usable_units, calendar_span, completeness
      # and maturity. Persisted rather than derived, so a historical
      # comparison can state what its baseline actually rested on
      # (STAT-015/021).
      t.integer :usable_units, null: false, default: 0
      t.integer :calendar_span_days, null: false, default: 0
      t.decimal :completeness
      t.text :maturity, null: false

      t.jsonb :source_summary, null: false, default: {}
      t.references :evidence_set, type: :uuid, foreign_key: true
      t.jsonb :version_tuple, null: false, default: {}
      t.text :fingerprint, null: false

      t.timestamps
    end

    add_index :baseline_instances,
      [ :organization_id, :subject_id, :definition_key, :definition_version, :as_of, :fingerprint ],
      unique: true, name: "index_baseline_instances_identity"
    add_index :baseline_instances, [ :organization_id, :subject_id, :as_of ],
      name: "index_baseline_instances_on_org_subject_as_of"

    # SC §21's three states. Maturity is visible (STAT-015) because a
    # comparison against an immature baseline is a materially weaker claim
    # than one against a mature baseline, and the reader must be able to see
    # which they are looking at.
    add_check_constraint :baseline_instances,
      "maturity IN ('immature', 'partial', 'mature')",
      name: "baseline_instances_maturity_check"
  end
end
