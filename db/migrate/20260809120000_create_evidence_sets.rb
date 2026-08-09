# frozen_string_literal: true

# Epic 001-09. HO §22.
#
# One consistent drilldown mechanism for every derived artifact. INV-3 says
# every derived value has exact lineage, and INV-4 says every provider-facing
# Finding can be drilled into — this is the single abstraction both rest on,
# so a Difference and a DerivedSignal expose their inputs the same way.
#
# The polymorphic reference is a deliberate v0.1 trade. HO §22: "if polymorphic
# evidence references become difficult to enforce safely, split by canonical
# record class later. For v0.1, correctness and inspectability outweigh perfect
# relational purity." Recorded here so the trade stays visible; HO §169 keeps
# it open for review.
class CreateEvidenceSets < ActiveRecord::Migration[8.1]
  PURPOSES = %w[
    derived_signal_inputs
    context_inputs
    baseline_inputs
    comparison_affected_inputs
    comparison_baseline_inputs
    investigation_snapshot
  ].freeze

  def change
    create_table :evidence_sets, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.text :purpose, null: false
      t.datetime :as_of, null: false

      # Digest of the ordered input identities. Two evidence sets over the
      # same inputs share a fingerprint, which is what lets a recomputation
      # recognise it would produce an identical result (HO §26 identity).
      t.text :fingerprint, null: false

      t.timestamps
    end

    add_index :evidence_sets, [ :organization_id, :purpose, :fingerprint ],
      name: "index_evidence_sets_on_org_purpose_fingerprint"

    add_check_constraint :evidence_sets,
      "purpose IN (#{PURPOSES.map { |p| "'#{p}'" }.join(', ')})",
      name: "evidence_sets_purpose_check"

    create_table :evidence_items, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :evidence_set, null: false, foreign_key: true, type: :uuid
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.text :record_type, null: false
      t.uuid :record_id, null: false
      t.text :role, null: false, default: "input"
      t.integer :ordinal

      t.timestamps
    end

    add_index :evidence_items, [ :evidence_set_id, :ordinal ],
      name: "index_evidence_items_on_set_and_ordinal"
    # The reverse question — "what was computed from this observation?" — is
    # what makes late-data invalidation possible in epic 003-10.
    add_index :evidence_items, [ :organization_id, :record_type, :record_id ],
      name: "index_evidence_items_on_record"
    add_index :evidence_items, [ :evidence_set_id, :record_type, :record_id, :role ],
      unique: true, name: "index_evidence_items_unique_per_set"
  end
end
