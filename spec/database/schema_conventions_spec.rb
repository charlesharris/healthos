# frozen_string_literal: true

require "rails_helper"

# Schema conventions that are cheap to hold and expensive to retrofit.
RSpec.describe "Schema conventions", type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  # Use text, never character varying.
  #
  # This is not stylistic. A CHECK constraint on a varchar column is not
  # round-trip stable: PostgreSQL normalizes `status IN ('a','b')` to
  #
  #   (status)::text = ANY ((ARRAY['a'::character varying, ...])::text[])
  #
  # and re-parsing that dumped text yields a *different* internal form, which
  # dumps again as
  #
  #   (status)::text = ANY (ARRAY[('a'::character varying)::text, ...])
  #
  # So a database built by running migrations and one built by loading
  # structure.sql produce different dumps, and the HO §124 schema-consistency
  # check fails with a diff that looks like a schema change but is not. On a
  # text column the same constraint renders as
  #
  #   status = ANY (ARRAY['a'::text, 'b'::text])
  #
  # which is a fixed point. PostgreSQL's own documentation notes there is no
  # performance difference between the two types.
  #
  # This cost most of an afternoon to diagnose through CI, hence the guard.
  it "uses text rather than character varying" do
    # schema_migrations and ar_internal_metadata are created by Rails itself
    # with varchar columns. We do not control their definition, and neither
    # carries a CHECK constraint, so they cannot trigger the problem.
    offenders = connection.select_rows(<<~SQL.squish)
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND data_type = 'character varying'
        AND table_name NOT IN ('schema_migrations', 'ar_internal_metadata')
      ORDER BY table_name, column_name
    SQL

    expect(offenders).to be_empty,
      "Use t.text, not t.string, for: " +
      offenders.map { |t, c| "#{t}.#{c}" }.join(", ") +
      ". A CHECK constraint on varchar is not round-trip stable and breaks " \
      "the schema-consistency check; see the comment in this spec."
  end

  # ADR-002 Decision 3b. Random v4 keys cause index write amplification on
  # append-heavy tables and destroy the physical time-ordering that BRIN would
  # need if the partitioning tripwires ever fire.
  it "defaults uuid primary keys to uuidv7()" do
    offenders = connection.select_rows(<<~SQL.squish)
      SELECT c.table_name, c.column_default
      FROM information_schema.columns c
      JOIN information_schema.table_constraints tc
        ON tc.table_name = c.table_name
       AND tc.table_schema = c.table_schema
       AND tc.constraint_type = 'PRIMARY KEY'
      JOIN information_schema.key_column_usage k
        ON k.constraint_name = tc.constraint_name
       AND k.column_name = c.column_name
      WHERE c.table_schema = 'public'
        AND c.data_type = 'uuid'
        AND (c.column_default IS NULL OR c.column_default NOT LIKE '%uuidv7%')
      ORDER BY c.table_name
    SQL

    expect(offenders).to be_empty,
      "uuid primary keys must default to uuidv7(): #{offenders.map(&:first).join(', ')}"
  end

  # HO §10.1 / §12: every tenant-facing table carries organization_id directly,
  # "even if derivable through another association".
  # Exemptions, each with a reason:
  #   organizations   is the tenant root; its own id is the tenant key
  #   users, sessions global by HO §10.2 — a user may belong to several orgs
  #   staff_members   platform-level, deliberately cross-tenant
  #   audit_events    organization_id is nullable because platform-level staff
  #                   actions genuinely have no tenant (see the migration)
  it "gives every tenant-facing table a NOT NULL organization_id" do
    exempt = %w[
      schema_migrations ar_internal_metadata
      organizations
      users sessions
      staff_members
      audit_events
    ].to_set

    tables = connection.tables.reject { |t| exempt.include?(t) }

    missing = tables.reject do |table|
      column = connection.columns(table).find { |c| c.name == "organization_id" }
      column && !column.null
    end

    expect(missing).to be_empty,
      "Missing NOT NULL organization_id: #{missing.join(', ')}. " \
      "If a table is genuinely not tenant-scoped, add it to the exempt list " \
      "with a reason."
  end
end
