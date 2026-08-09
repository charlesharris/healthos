# frozen_string_literal: true

# Epic 001-07. HO §16, §21 (provenance), §28 (missingness taxonomy).
#
# The highest-volume table in the system and the one every analytical claim
# eventually resolves to. Append-only (INV-2): a correction arrives as a new
# observation from a new envelope, never as an edit.
class CreateObservations < ActiveRecord::Migration[8.1]
  # HO §28. Ten states, not a boolean — "do not use one generic `missing`
  # boolean". The distinction between device_not_reporting and
  # manual_entry_absent is the difference between an instrumentation finding
  # and a behavioural one (STAT-003, STAT-010).
  QUALITY_STATES = %w[
    observed
    not_expected
    expected_but_missing
    source_unavailable
    device_not_reporting
    manual_entry_absent
    invalid_measurement
    excluded_by_rule
    late_not_yet_arrived
    unknown
  ].freeze

  RECORDING_METHODS = %w[
    device_automatic device_manual_transcription manual_entry
    clinician_entered imported_batch unknown
  ].freeze

  def change
    create_table :observations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      t.references :observation_group, foreign_key: true, type: :uuid

      # HO §16: "numeric telemetry can use PostgreSQL numeric for correctness
      # and simplicity." Deliberately not float — a BP of 142 must never come
      # back as 141.99999999999997, and binary floating point has no business
      # anywhere near clinical evidence.
      t.decimal :value_numeric
      t.text :value_text
      t.text :value_code
      t.text :unit

      t.datetime :observed_at, null: false
      t.datetime :observed_end_at
      # Retained alongside observed_at because the subject's offset at the
      # moment of measurement is not recoverable from a UTC timestamp plus a
      # current timezone — DST and relocation both break that. HO §121 makes
      # timezone boundaries a required regression case.
      t.integer :timezone_offset_minutes

      # HO §21: provenance is not a text note. Every canonical record exposes
      # its raw source, source identity, device, recording method, normalizer
      # and version, original timestamps, and ingestion timestamp.
      t.references :source, null: false, foreign_key: true, type: :uuid
      t.references :device, foreign_key: true, type: :uuid
      t.references :raw_envelope, null: false, foreign_key: true, type: :uuid
      t.text :source_record_id, null: false
      t.text :recording_method, null: false, default: "unknown"
      t.text :measurement_protocol

      t.text :quality_state, null: false, default: "observed"
      t.jsonb :quality_flags, null: false, default: {}

      t.datetime :source_modified_at
      t.datetime :ingested_at
      t.datetime :normalized_at, null: false

      t.text :normalizer_key, null: false
      t.integer :normalizer_version, null: false

      t.timestamps
    end

    add_index :observations, [ :organization_id, :public_id ], unique: true

    # HO §110's index plan.
    add_index :observations, [ :organization_id, :subject_id, :semantic_key, :observed_at ],
      order: { observed_at: :desc }, name: "index_observations_on_org_subject_key_time"
    add_index :observations, [ :organization_id, :source_id, :source_record_id ],
      name: "index_observations_on_org_source_record"
    # raw_envelope_id and observation_group_id are already indexed by
    # t.references above.

    # Normalization must be idempotent (§96): re-running a normalizer over the
    # same envelope produces no duplicate canonical rows. The constraint, not
    # the service, is the authority (S2C-022). semantic_version and
    # normalizer_version are part of the key so that reprocessing under a NEW
    # version legitimately produces new rows alongside the old ones, which is
    # what HO §155 requires of reprocessing.
    add_index :observations,
      [ :raw_envelope_id, :semantic_key, :semantic_version, :normalizer_version, :observed_at ],
      unique: true, name: "index_observations_normalization_identity"

    add_check_constraint :observations,
      "quality_state IN (#{QUALITY_STATES.map { |s| "'#{s}'" }.join(', ')})",
      name: "observations_quality_state_check"

    add_check_constraint :observations,
      "recording_method IN (#{RECORDING_METHODS.map { |s| "'#{s}'" }.join(', ')})",
      name: "observations_recording_method_check"

    # HO §16: "use a CHECK constraint so value representation is internally
    # valid."
    #
    # An observed observation must carry exactly one value representation. A
    # non-observed one must carry none — this is what makes STAT-002 ("missing
    # != zero") structurally enforceable rather than a convention: there is no
    # way to record an expected_but_missing row with a value of 0.
    add_check_constraint :observations, <<~SQL.squish, name: "observations_value_representation_check"
      (
        quality_state = 'observed'
        AND (
          (value_numeric IS NOT NULL)::int
          + (value_text IS NOT NULL)::int
          + (value_code IS NOT NULL)::int
        ) = 1
      ) OR (
        quality_state <> 'observed'
        AND value_numeric IS NULL
        AND value_text IS NULL
        AND value_code IS NULL
      )
    SQL

    # A numeric value without a unit is uninterpretable, and unit confusion is
    # a classic source of silent clinical error.
    add_check_constraint :observations,
      "value_numeric IS NULL OR unit IS NOT NULL",
      name: "observations_numeric_requires_unit_check"
  end
end
