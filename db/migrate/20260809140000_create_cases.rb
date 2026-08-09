# frozen_string_literal: true

# Epic 001-11. HO §35–39.
#
# The Case is the stateful unit of human work (S2C-004, INV-25). Signals
# accumulate freely as machine evidence; a Case is the assertion that a person
# should look at something. Many Signals → few Cases (S2C-005).
class CreateCases < ActiveRecord::Migration[8.1]
  STATUSES = %w[new triaged investigating watching waiting_external resolved dismissed].freeze
  PRIORITIES = %w[now today routine watch].freeze
  RELATIONSHIPS = %w[trigger supporting contextual reopening].freeze

  def change
    # HO §35. The serialization point for correlation.
    #
    # A row lock rather than an in-process mutex because it works across
    # workers, survives multi-process deployment, is visible and testable, and
    # avoids the hash-collision concerns of homemade advisory-lock keys.
    # PostgreSQL remains the correctness authority (S2C-022).
    create_table :case_correlation_scopes, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid
      t.text :domain_key, null: false

      t.timestamps
    end

    add_index :case_correlation_scopes, [ :organization_id, :subject_id, :domain_key ],
      unique: true, name: "index_case_correlation_scopes_identity"

    create_table :cases, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :public_id, null: false
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid

      t.text :domain_key, null: false
      # NOT a Rails STI `type` column (HO §36, CLAUDE.md forbidden patterns).
      # Case types are domain-pack data, not Ruby subclasses; STI would put
      # domain vocabulary into the platform's class hierarchy.
      t.text :case_type, null: false

      t.text :title
      t.text :summary

      t.text :status, null: false, default: "new"
      t.text :review_priority, null: false, default: "routine"
      # S2C-012: store WHY a Case has its priority. An unexplained ranking is
      # exactly what HO §159 and S2C-023 forbid.
      t.jsonb :priority_reasons, null: false, default: []

      t.references :owner, type: :uuid, foreign_key: { to_table: :users }
      t.references :team, type: :uuid, foreign_key: true

      t.datetime :started_at, null: false
      t.datetime :detected_at, null: false
      t.datetime :last_signal_at

      # Analysis pointers. Nullable because S2C-019 requires a Case to remain
      # operationally visible when analysis fails or has not run — `failed` is
      # never conflated with `insufficient_evidence`.
      t.text :evidence_level
      t.text :data_quality_state
      t.text :baseline_maturity
      t.text :analysis_status, null: false, default: "not_started"
      t.datetime :analysis_as_of

      t.uuid :current_context_id
      t.uuid :current_baseline_instance_id
      t.uuid :current_comparison_id
      t.uuid :top_finding_id

      t.datetime :last_reviewed_at
      t.datetime :watch_until
      t.datetime :resolved_at

      # Optimistic locking for operator edits. Correlation uses the pessimistic
      # scope lock instead; these guard different races — one machine, one
      # human.
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :cases, [ :organization_id, :public_id ], unique: true
    # HO §110's queue index plan.
    add_index :cases, [ :organization_id, :status, :review_priority, :detected_at ],
      name: "index_cases_on_org_status_priority_time"
    add_index :cases, [ :organization_id, :subject_id, :domain_key, :status ],
      name: "index_cases_on_org_subject_domain_status"
    add_index :cases, [ :organization_id, :team_id, :status, :review_priority ],
      name: "index_cases_on_org_team_status_priority"
    add_index :cases, [ :organization_id, :owner_id, :status ],
      name: "index_cases_on_org_owner_status"

    add_check_constraint :cases,
      "status IN (#{STATUSES.map { |s| "'#{s}'" }.join(', ')})",
      name: "cases_status_check"
    add_check_constraint :cases,
      "review_priority IN (#{PRIORITIES.map { |p| "'#{p}'" }.join(', ')})",
      name: "cases_review_priority_check"
    add_check_constraint :cases,
      "analysis_status IN ('not_started', 'pending', 'current', 'stale', 'failed', 'insufficient_evidence')",
      name: "cases_analysis_status_check"

    create_table :case_signals, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :case, null: false, foreign_key: true, type: :uuid
      t.references :signal, null: false, foreign_key: true, type: :uuid

      t.text :relationship, null: false, default: "trigger"
      t.datetime :attached_at, null: false
      # S2C-012 / HO §158: why this Signal attached to this Case. Support must
      # be able to explain a correlation after the fact without re-deriving it.
      t.jsonb :explanation, null: false, default: {}

      t.timestamps
    end

    add_index :case_signals, [ :case_id, :signal_id ], unique: true,
      name: "index_case_signals_unique"
    add_index :case_signals, :signal_id, name: "index_case_signals_on_signal"

    add_check_constraint :case_signals,
      "relationship IN (#{RELATIONSHIPS.map { |r| "'#{r}'" }.join(', ')})",
      name: "case_signals_relationship_check"

    # HO §39. The authoritative Case workflow history — append-only (S2C-010,
    # INV-26).
    create_table :case_events, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :case, null: false, foreign_key: true, type: :uuid

      t.text :event_type, null: false
      t.text :actor_type, null: false, default: "system"
      t.uuid :actor_id

      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false, default: {}

      # ADR-002 Decision 4c: hash chain, so mutation is detectable even by an
      # actor with superuser access. Low volume, high scrutiny.
      t.text :prev_hash
      t.text :row_hash

      t.timestamps
    end

    add_index :case_events, [ :case_id, :occurred_at ], name: "index_case_events_on_case_and_time"
    add_index :case_events, [ :organization_id, :event_type, :occurred_at ],
      name: "index_case_events_on_org_type_time"
  end
end
