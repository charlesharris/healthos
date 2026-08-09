# frozen_string_literal: true

require "rails_helper"

# MigratorConnection lives in spec/support/migrator_connection.rb — several
# specs need an owner-level connection now, not just this one.

# ADR-002 Decision 4a — append-only enforced by privilege revocation.
#
# Two jobs here:
#
#   1. Completeness. Every table in the database must be classified in
#      db/privileges.yml. This is the check that matters most over time: an
#      earlier draft of ADR-002 classified tables from memory and missed seven
#      of them. A new table now fails the build until someone decides what it
#      is.
#
#   2. Enforcement. Not "was a GRANT issued" but "does PostgreSQL actually
#      refuse the write". The mechanism spec below creates a real table and
#      attempts a real UPDATE as healthos_app.
RSpec.describe "Database privileges", type: :model do
  let(:manifest) { YAML.load_file(Rails.root.join("db/privileges.yml")) }
  let(:append_only) { Array(manifest["append_only"]) }
  let(:mutable) { Array(manifest["mutable"]) + Array(manifest["system"]) }
  let(:column_updates) { manifest["column_updates"] || {} }
  let(:connection) { ActiveRecord::Base.connection }

  def app_privilege?(table, privilege)
    connection.select_value(
      "SELECT has_table_privilege('healthos_app', #{connection.quote(table)}, #{connection.quote(privilege)})"
    )
  end

  describe "manifest completeness" do
    it "classifies every table that exists in the database" do
      classified = (append_only + mutable).to_set
      unclassified = connection.tables.reject { |t| classified.include?(t) }

      expect(unclassified).to be_empty,
        "Unclassified tables: #{unclassified.join(', ')}.\n" \
        "Add each to `append_only` or `mutable` in db/privileges.yml. " \
        "See ADR-002 Decision 4a for how to decide."
    end

    it "does not classify a table as both append-only and mutable" do
      expect(append_only & mutable).to be_empty
    end

    it "only grants column-level UPDATE on append-only tables" do
      expect(column_updates.keys - append_only).to be_empty
    end
  end

  describe "append-only tables" do
    it "denies UPDATE and DELETE to the application role" do
      existing = append_only & connection.tables
      skip "no append-only tables created yet" if existing.empty?

      offenders = existing.reject do |table|
        # A table with a column-level UPDATE grant still reports false for
        # table-level UPDATE, which is exactly the distinction we want.
        !app_privilege?(table, "UPDATE") && !app_privilege?(table, "DELETE")
      end

      expect(offenders).to be_empty,
        "These append-only tables are writable by healthos_app: #{offenders.join(', ')}"
    end

    it "still allows SELECT and INSERT" do
      existing = append_only & connection.tables
      skip "no append-only tables created yet" if existing.empty?

      unreadable = existing.reject { |t| app_privilege?(t, "SELECT") && app_privilege?(t, "INSERT") }

      expect(unreadable).to be_empty
    end
  end

  describe "mutable tables" do
    it "allows full DML to the application role" do
      existing = mutable & connection.tables
      skip "no mutable tables created yet" if existing.empty?

      broken = existing.reject do |table|
        %w[SELECT INSERT UPDATE DELETE].all? { |p| app_privilege?(table, p) }
      end

      expect(broken).to be_empty,
        "These mutable tables are missing DML for healthos_app: #{broken.join(', ')}"
    end
  end

  # The mechanism itself, proven end-to-end against a real table rather than
  # deferred until domain tables exist in a later epic. If this passes, the
  # thirty-odd tables arriving in epics 001-004 inherit a verified guarantee.
  describe "enforcement mechanism" do
    # Transactional fixtures wrap every registered connection pool, which would
    # leave the probe table's CREATE uncommitted on the migrator connection and
    # therefore invisible to the app connection doing the asserting. DDL is not
    # transactional here by design; the after hook cleans up instead.
    self.use_transactional_tests = false

    let(:probe_table) { "privilege_probe" }

    # A second connection owning the table, since the suite itself runs as the
    # unprivileged healthos_app role and therefore cannot CREATE.
    let(:migrator) do
      MigratorConnection.establish_connection(
        ActiveRecord::Base.connection_db_config.configuration_hash
          .merge(username: "healthos_migrator")
      )
      MigratorConnection.connection
    end

    before do
      migrator.execute("DROP TABLE IF EXISTS #{probe_table}")
      migrator.execute(<<~SQL)
        CREATE TABLE #{probe_table} (
          id uuid PRIMARY KEY DEFAULT uuidv7(),
          note text
        )
      SQL
      migrator.execute("GRANT SELECT, INSERT ON #{probe_table} TO healthos_app")
      migrator.execute("GRANT UPDATE (note) ON #{probe_table} TO healthos_app")
    end

    after do
      migrator.execute("DROP TABLE IF EXISTS #{probe_table}")
      migrator.disconnect!
    end

    it "permits INSERT" do
      expect {
        connection.execute("INSERT INTO #{probe_table} (note) VALUES ('first')")
      }.not_to raise_error
    end

    it "refuses DELETE at the database, not merely in Ruby" do
      connection.execute("INSERT INTO #{probe_table} (note) VALUES ('keep')")

      expect {
        connection.execute("DELETE FROM #{probe_table}")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    it "refuses UPDATE of a column outside the annotation grant" do
      connection.execute("INSERT INTO #{probe_table} (note) VALUES ('keep')")

      expect {
        connection.execute("UPDATE #{probe_table} SET id = uuidv7()")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    # ADR-002 Decision 4a-ii, resolved 2026-08-08: annotation columns stay
    # editable. Asserted in both directions because a column-level grant is
    # easy to widen by accident.
    it "permits UPDATE of a column inside the annotation grant" do
      connection.execute("INSERT INTO #{probe_table} (note) VALUES ('before')")

      expect {
        connection.execute("UPDATE #{probe_table} SET note = 'after'")
      }.not_to raise_error
    end

    it "generates time-ordered UUIDv7 keys" do
      connection.execute("INSERT INTO #{probe_table} (note) VALUES ('a')")
      sleep 0.01
      connection.execute("INSERT INTO #{probe_table} (note) VALUES ('b')")

      ids = connection.select_values("SELECT id FROM #{probe_table} ORDER BY note")

      # UUIDv7 embeds a millisecond timestamp in its leading bits, so lexical
      # order matches insertion order. This is the property ADR-002 Decision 3b
      # depends on for index locality and future BRIN viability.
      expect(ids).to eq(ids.sort)
      expect(ids.first[14]).to eq("7") # version nibble
    end
  end
end
