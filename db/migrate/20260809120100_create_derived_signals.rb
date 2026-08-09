# frozen_string_literal: true

# Epic 001-09. HO §26: "a DerivedSignal is a canonical reproducible
# calculation."
#
# This is the table that replaces what a time-series database would call a
# continuous aggregate — and the reason ADR-001 rejects Timescale outright. A
# continuous aggregate is mutable and carries no algorithm version, digest, or
# lineage, so it cannot satisfy INV-3 or be pinned by a saved Investigation.
# This one can: every row names the exact algorithm that produced it and the
# exact inputs it consumed.
class CreateDerivedSignals < ActiveRecord::Migration[8.1]
  STATUSES = %w[computed insufficient_input superseded failed].freeze

  def change
    create_table :derived_signals, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false

      t.decimal :value_numeric
      t.text :value_text
      t.jsonb :value_json
      t.text :unit

      # INV-8: derived-signal algorithms are versioned. The digest catches a
      # behaviour change made without a version bump, the same protection
      # bin/definitions verify gives semantic definitions (HO §25).
      t.text :algorithm_key, null: false
      t.integer :algorithm_version, null: false
      t.text :algorithm_digest, null: false

      t.references :evidence_set, foreign_key: true, type: :uuid

      # Denominators are persisted, never recomputed (STAT-021, ADR-001 §5b).
      # A derived value that cannot state how many usable inputs it had is not
      # interpretable, and recomputing the count later would answer a
      # different question than the one the value was computed under.
      t.integer :usable_input_count, null: false, default: 0
      t.integer :raw_input_count, null: false, default: 0

      t.text :status, null: false, default: "computed"

      t.datetime :computed_at, null: false
      t.datetime :as_of, null: false

      t.timestamps
    end

    # HO §26 identity: subject + semantic key/version + window + algorithm
    # version + as_of/fingerprint. Enforced in the database so a retried job
    # cannot produce a second row (HO §96, S2C-020/022).
    add_index :derived_signals,
      [ :organization_id, :subject_id, :semantic_key, :semantic_version,
        :window_started_at, :window_ended_at, :algorithm_version ],
      unique: true, name: "index_derived_signals_identity"

    # HO §110's index plan.
    add_index :derived_signals,
      [ :organization_id, :subject_id, :semantic_key, :window_ended_at ],
      order: { window_ended_at: :desc },
      name: "index_derived_signals_on_org_subject_key_time"

    add_check_constraint :derived_signals,
      "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(', ')})",
      name: "derived_signals_status_check"

    # STAT-002 again, at the derived layer: a signal with no usable inputs
    # carries no value. There is no way to record "zero readings, therefore
    # zero mmHg".
    add_check_constraint :derived_signals, <<~SQL.squish, name: "derived_signals_value_representation_check"
      (status = 'computed' AND (value_numeric IS NOT NULL OR value_text IS NOT NULL OR value_json IS NOT NULL))
      OR (status <> 'computed' AND value_numeric IS NULL AND value_text IS NULL)
    SQL

    add_check_constraint :derived_signals,
      "window_ended_at >= window_started_at",
      name: "derived_signals_window_order_check"
  end
end
