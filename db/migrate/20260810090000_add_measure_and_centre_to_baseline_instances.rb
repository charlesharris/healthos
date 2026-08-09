# frozen_string_literal: true

# `baseline_instances` could not say WHAT it was a baseline of, or what the
# baseline actually was.
#
# 003-07 built the table from SC §21's list — usable_units, calendar_span,
# completeness, maturity — which is what a reader needs to judge a baseline's
# *sufficiency*. It is not enough to use one. The table had no semantic key,
# so "this subject's systolic baseline" was not a query it could answer, and
# no centre or scale, so SC §29's robust standardized effect had nothing to
# compute from. `Baselines::Definition::Result` has carried all four since
# 003-08; the table simply never learned them.
#
# Surfaced by 002x-02: comparing a subject against the distribution of other
# subjects' baselines needs each baseline's central value, per measure.
#
# MIGRATION NOTES (CLAUDE.md):
#   Locking      — ADD COLUMN with no default and no volatile expression is
#                  metadata-only on PostgreSQL 11+; no table rewrite.
#   Backfill     — none. Nothing materializes BaselineInstance rows yet, so
#                  the table is empty in every environment; the NOT NULLs are
#                  therefore safe to add outright rather than in three steps.
#   Index build  — one composite index for the cohort read ("every subject's
#                  baseline for this measure as of this instant"). Created
#                  non-concurrently because the table is empty.
#   Rollback     — `remove_column` x5 plus the index; no data loss, because
#                  there is no data.
class AddMeasureAndCentreToBaselineInstances < ActiveRecord::Migration[8.1]
  def change
    change_table :baseline_instances, bulk: true do |t|
      # WHICH measure. Without it a subject's baselines for systolic and pulse
      # are distinguishable only by their input fingerprint, which is an
      # identity, not a query.
      t.text :semantic_key, null: false
      t.integer :semantic_version, null: false

      # WHAT the baseline was. A centre without a scale cannot support a
      # standardized effect, so both travel or neither is useful — and both
      # stay nullable, because an immature baseline legitimately has no
      # dispersion (SC §22's aggregation needs three days to have one) and
      # STAT-002 forbids inventing a stand-in.
      t.decimal :central_value
      t.decimal :dispersion
      t.text :unit
    end

    add_index :baseline_instances,
              [ :organization_id, :semantic_key, :as_of ],
              name: "index_baseline_instances_on_org_measure_as_of"
  end
end
