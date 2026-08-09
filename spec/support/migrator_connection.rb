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
end
