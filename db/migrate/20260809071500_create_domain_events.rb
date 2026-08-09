# frozen_string_literal: true

# Epic 001-03. Transactional outbox (HO §49, S2C-021).
#
# Protects against "DB committed but enqueue failed", which HO §49 calls out
# as especially likely here because job storage lives in a separate database
# (HO §6.3) — so the state change and the enqueue can never share a
# transaction. The event row commits with the state change; a dispatcher turns
# it into an Active Job afterwards.
#
# NOT append-only: dispatched_at, attempts and last_error are updated by the
# dispatcher. Classified `mutable` in db/privileges.yml, which is why the
# ADR-002 Decision 4a table list exempts it.
class CreateDomainEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :domain_events, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.string :aggregate_type, null: false
      t.uuid :aggregate_id, null: false
      t.string :event_type, null: false

      # IDs and non-PHI metadata only. CLAUDE.md: "No PHI in technical logs,
      # job arguments, metric labels, or error reports. Pass IDs to jobs,
      # never payloads." The dispatcher passes the event id to the handler,
      # so this column must never be the transport for health data.
      t.jsonb :payload, null: false, default: {}

      t.datetime :occurred_at, null: false
      t.datetime :dispatched_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error

      t.timestamps
    end

    # The dispatcher's hot query: oldest undispatched first. Partial, so the
    # index stays small as dispatched events accumulate — they are the
    # overwhelming majority.
    add_index :domain_events, [ :occurred_at, :id ],
      where: "dispatched_at IS NULL",
      name: "index_domain_events_pending"

    # Provenance lookups: "what happened to this aggregate?"
    add_index :domain_events, [ :organization_id, :aggregate_type, :aggregate_id, :occurred_at ],
      name: "index_domain_events_on_aggregate"

    add_index :domain_events, [ :organization_id, :event_type, :occurred_at ],
      name: "index_domain_events_on_org_and_type"
  end
end
