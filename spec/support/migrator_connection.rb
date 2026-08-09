# frozen_string_literal: true

# Owner-level connection for specs that must CREATE, GRANT, or DELETE from
# append-only tables during setup and teardown.
#
# The suite itself runs as the unprivileged healthos_app role (ADR-002
# Decision 4a-iv), which is the point — append-only enforcement is exercised
# by every example. A few specs legitimately need more: building a probe
# table, or cleaning up after a spec that runs without transactional
# fixtures and therefore commits for real.
class MigratorConnection < ActiveRecord::Base
  self.abstract_class = true

  def self.connect!
    establish_connection(
      ActiveRecord::Base.connection_db_config.configuration_hash
        .merge(username: "healthos_migrator")
    )
    connection
  end

  # Deletes in the given order, as migrator. Order matters: foreign keys mean
  # children go first, and most of these tables refuse DELETE to the app role.
  def self.truncate!(tables)
    conn = connect!
    tables.each { |table| conn.execute("DELETE FROM #{table}") }
  ensure
    remove_connection
  end

  # Empties every tenant-facing table, in an order derived from the schema's
  # foreign keys rather than hand-maintained.
  #
  # For specs that seed broadly enough that naming the tables is a losing
  # game: a hand-written list is wrong the moment someone adds a table, and it
  # fails as an FK violation partway through teardown, leaving the database
  # half-cleaned and the next spec failing somewhere unrelated.
  def self.wipe_tenant_data!
    conn = connect!
    tables = conn.tables - %w[schema_migrations ar_internal_metadata]

    ordered = topological_order(conn, tables)
    ordered.each { |table| conn.execute("DELETE FROM #{conn.quote_table_name(table)}") }
  ensure
    remove_connection
  end

  # Dependents first. A table is safe to delete once nothing still in the set
  # references it.
  def self.topological_order(conn, tables)
    remaining = tables.to_h do |table|
      [ table, conn.foreign_keys(table).map(&:to_table).select { |t| tables.include?(t) } - [ table ] ]
    end

    ordered = []
    until remaining.empty?
      leaves = remaining.keys.reject do |table|
        remaining.except(table).values.any? { |deps| deps.include?(table) }
      end
      raise "cycle in foreign keys among #{remaining.keys.join(', ')}" if leaves.empty?

      ordered.concat(leaves)
      remaining.except!(*leaves)
    end

    ordered
  end
end
