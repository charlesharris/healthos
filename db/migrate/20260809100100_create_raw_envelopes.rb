# frozen_string_literal: true

# Epic 001-05. HO §13.1: "preserve source truth before transformation."
#
# INV-1 — raw source truth is preserved. This is the most strictly append-only
# table in the system: the app role has SELECT and INSERT only (ADR-002 4a),
# and the payload itself lives in an object-locked bucket (4b), so neither the
# metadata nor the bytes can be altered after the fact.
class CreateRawEnvelopes < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_envelopes, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      # Nullable until identity resolution — HO §13.1. An envelope is stored
      # before we know whose it is, because storing raw truth must never be
      # blocked by our ability to interpret it.
      t.references :subject, foreign_key: true, type: :uuid
      t.references :source, null: false, foreign_key: true, type: :uuid

      t.text :source_record_id, null: false
      t.text :source_record_version

      t.text :content_type, null: false
      t.text :object_key, null: false
      # SHA-256 of the stored payload. Verified on read (ADR-002 4b), so
      # tampering with either the object store or this row is detectable
      # rather than merely discouraged.
      t.text :content_hash, null: false

      t.datetime :observed_at
      t.datetime :source_modified_at
      t.datetime :received_at, null: false
      t.datetime :ingested_at

      t.text :adapter_key, null: false
      t.text :adapter_version, null: false

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # HO §13.1 / §14: the identity that makes ingestion idempotent. Retries
    # must not create duplicate canonical data, and "database constraints are
    # the final authority" — so this is a unique index, not a service-layer
    # check.
    #
    # source_record_version is part of the key and may be NULL. In PostgreSQL
    # NULLs are distinct in a unique index by default, which would let the
    # same versionless record insert repeatedly; NULLS NOT DISTINCT closes
    # that hole. HO §13.1 anticipates it: "when a source lacks versions,
    # derive stable semantic identity and content hash."
    add_index :raw_envelopes,
      [ :organization_id, :source_id, :source_record_id, :source_record_version ],
      unique: true, nulls_not_distinct: true,
      name: "index_raw_envelopes_identity"

    add_index :raw_envelopes, [ :organization_id, :public_id ], unique: true
    add_index :raw_envelopes, [ :organization_id, :received_at ]
    add_index :raw_envelopes, [ :organization_id, :subject_id, :observed_at ],
      name: "index_raw_envelopes_on_org_subject_time"
  end
end
