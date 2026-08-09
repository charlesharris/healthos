# frozen_string_literal: true

# Epic 002-18 to 002-20. HO §41 (dispositions), §45 (watch conditions),
# §91 (workflow actions).
class CreateCaseLifecycleTables < ActiveRecord::Migration[8.1]
  DISPOSITION_CODES = %w[
    action_taken expected_change instrumentation_issue data_quality_issue
    already_known not_actionable insufficient_evidence duplicate
    false_positive escalated_external
  ].freeze

  CONDITION_TYPES = %w[time_elapsed new_observation_count new_signal threshold_crossed].freeze

  def change
    # HO §46. S2C-015: closing work records what happened.
    #
    # A separate record rather than a column on `cases`, because S2C-016
    # requires a reopened Case to keep its prior disposition visible. A column
    # would be overwritten on the second resolution and the history would be
    # gone.
    create_table :case_dispositions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :case, null: false, foreign_key: true, type: :uuid
      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.text :code, null: false
      t.text :notes
      t.text :action_type
      t.text :external_reference

      t.datetime :disposed_at, null: false

      t.timestamps
    end

    add_index :case_dispositions, [ :case_id, :disposed_at ],
      name: "index_case_dispositions_on_case_and_time"
    add_index :case_dispositions, [ :organization_id, :code, :disposed_at ],
      name: "index_case_dispositions_on_org_code_time"

    # HO §46: "do not allow arbitrary customer disposition taxonomies until
    # product reporting semantics are understood." A free-text code would make
    # the resolution-feedback loop in HO §43 unanalysable across customers.
    add_check_constraint :case_dispositions,
      "code IN (#{DISPOSITION_CODES.map { |c| "'#{c}'" }.join(', ')})",
      name: "case_dispositions_code_check"

    # HO §45. S2C-014: watching is first-class and carries an explicit
    # reevaluation condition.
    #
    # "Watching" means review occurred but evidence does not justify closure
    # or immediate action — a genuine third answer beside act and close, and
    # the one STAT-036's "we do not know yet" needs somewhere to live.
    create_table :watch_conditions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :case, null: false, foreign_key: true, type: :uuid
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }

      t.text :condition_type, null: false
      t.jsonb :parameters, null: false, default: {}

      t.datetime :expires_at
      t.datetime :satisfied_at

      t.timestamps
    end

    add_index :watch_conditions, [ :case_id, :satisfied_at ],
      name: "index_watch_conditions_on_case_and_satisfied"
    # The evaluation job's hot query: unsatisfied conditions due for a look.
    add_index :watch_conditions, [ :organization_id, :expires_at ],
      where: "satisfied_at IS NULL",
      name: "index_watch_conditions_pending"

    add_check_constraint :watch_conditions,
      "condition_type IN (#{CONDITION_TYPES.map { |c| "'#{c}'" }.join(', ')})",
      name: "watch_conditions_condition_type_check"

    # HO §91. Schema only here; the webhook adapter lands with 005-06.
    #
    # S2C-024: external calls happen AFTER commit, never inside a transaction.
    # This row is the durable intent; dispatch is a separate, retryable step,
    # which is the same shape as the outbox and for the same reason.
    create_table :workflow_actions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :case, null: false, foreign_key: true, type: :uuid
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users }

      t.text :action_type, null: false
      t.text :status, null: false, default: "pending"
      t.jsonb :parameters, null: false, default: {}
      t.jsonb :result, null: false, default: {}

      # Idempotency key so a retried dispatch cannot fire the same external
      # action twice (S2C-020, HO §91).
      t.text :idempotency_key, null: false
      t.integer :attempts, null: false, default: 0
      t.text :last_error

      t.datetime :dispatched_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :workflow_actions, [ :organization_id, :idempotency_key ], unique: true,
      name: "index_workflow_actions_idempotency"
    add_index :workflow_actions, [ :case_id, :created_at ],
      name: "index_workflow_actions_on_case_and_time"

    add_check_constraint :workflow_actions,
      "status IN ('pending', 'dispatched', 'succeeded', 'failed', 'cancelled')",
      name: "workflow_actions_status_check"
  end
end
