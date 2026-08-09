# frozen_string_literal: true

# Reconciles database privileges from db/privileges.yml.
# ADR-002 Decision 4a / 4a-v.
#
# Must run as a role that can GRANT on the tables — i.e. the owner,
# healthos_migrator. bin/setup, bin/test and the CI workflow set
# HEALTHOS_DB_USER accordingly.
#
# Idempotent by construction: every table is REVOKEd to a known-empty state and
# then re-GRANTed from the manifest, so removing a manifest entry actually
# withdraws the privilege rather than leaving it stranded.

module HealthosPrivileges
  APP      = "healthos_app"
  ADMIN    = "healthos_admin"
  MIGRATOR = "healthos_migrator"

  module_function

  def manifest
    YAML.load_file(Rails.root.join("db/privileges.yml"))
  end

  def apply!(conn)
    spec          = manifest
    append_only   = Array(spec["append_only"])
    mutable       = Array(spec["mutable"]) + Array(spec["system"])
    column_grants = spec["column_updates"] || {}
    present       = conn.tables.to_set

    applied = 0
    skipped = 0

    # Without USAGE on the schema the app role cannot reach the tables at all,
    # regardless of table-level grants.
    conn.execute("GRANT USAGE ON SCHEMA public TO #{APP}, #{ADMIN}")

    # On default-deny: PostgreSQL already grants nothing on a new table to
    # roles other than the owner, so an unclassified table is unwritable by
    # healthos_app without any action from us. This ALTER DEFAULT PRIVILEGES
    # guards the other direction — it stops a future blanket convenience grant
    # from silently making every new table writable.
    conn.execute(<<~SQL.squish)
      ALTER DEFAULT PRIVILEGES FOR ROLE #{MIGRATOR} IN SCHEMA public
        REVOKE ALL ON TABLES FROM #{APP}
    SQL

    (append_only + mutable).each do |table|
      unless present.include?(table)
        skipped += 1
        next
      end

      quoted = conn.quote_table_name(table)

      conn.execute("REVOKE ALL ON #{quoted} FROM #{APP}")
      conn.execute("REVOKE ALL ON #{quoted} FROM #{ADMIN}")

      if append_only.include?(table)
        conn.execute("GRANT SELECT, INSERT ON #{quoted} TO #{APP}")

        # ADR-002 4a-ii: column-level UPDATE for annotation fields only. The
        # pinned evidence columns stay immutable (HO §188, STAT-040/041).
        cols = Array(column_grants[table])
        if cols.any?
          list = cols.map { |c| conn.quote_column_name(c) }.join(", ")
          conn.execute("GRANT UPDATE (#{list}) ON #{quoted} TO #{APP}")
        end
      else
        conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{quoted} TO #{APP}")
      end

      # The admin role performs retention and support operations on every
      # table, including deletes the app role cannot do (Decision 4a-iii).
      conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{quoted} TO #{ADMIN}")
      applied += 1
    end

    conn.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{APP}, #{ADMIN}")

    [ applied, skipped ]
  end

  # Applies privileges across every database configured for `env`.
  #
  # The env is passed explicitly rather than read from Rails.env because
  # `db:test:prepare` runs with Rails.env == "development" while operating on
  # the test databases — reading Rails.env there would silently privilege the
  # wrong cluster and leave the test databases unusable by healthos_app.
  def apply_to_env!(env)
    original = ActiveRecord::Base.connection_db_config

    ActiveRecord::Base.configurations.configs_for(env_name: env).each do |config|
      ActiveRecord::Base.establish_connection(config)
      conn = ActiveRecord::Base.connection

      # Rails' internal bookkeeping tables must exist before the app role can
      # boot, and creating them needs CREATE on schema public — which only the
      # migrator has. Normally schema load handles this, but a structure.sql
      # with no migrations in it leaves them absent, and the app role then
      # fails on `check_all_pending!` with a confusing privilege error rather
      # than a schema error. Cheap to make unconditional and idempotent.
      if config.name == "primary"
        pool = ActiveRecord::Base.connection_pool
        pool.schema_migration.create_table
        pool.internal_metadata.create_table
      end

      # The manifest governs the primary database only. The queue database
      # holds Solid Queue's job state, which is mutable by nature and owned by
      # the gem's own schema — health evidence never lives there, so blanket
      # DML is correct rather than a gap in coverage.
      if config.name == "primary"
        applied, skipped = apply!(conn)
        puts "[db:privileges] #{conn.current_database}: applied to #{applied} table(s)"
        if skipped.positive?
          puts "[db:privileges] #{skipped} manifest table(s) not yet created " \
               "(expected — the manifest deliberately leads the migrations)"
        end
      else
        grant_all!(conn)
        puts "[db:privileges] #{conn.current_database}: full DML granted (#{config.name}, gem-managed)"
      end
    end
  ensure
    ActiveRecord::Base.establish_connection(original) if original
  end

  # For gem-managed databases (Solid Queue's job state). No health evidence
  # lives here, so there is nothing to make append-only.
  def grant_all!(conn)
    conn.execute("GRANT USAGE, CREATE ON SCHEMA public TO #{APP}")
    conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{APP}")
    conn.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{APP}")
    conn.execute(<<~SQL.squish)
      ALTER DEFAULT PRIVILEGES FOR ROLE #{MIGRATOR} IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{APP}
    SQL
    conn.execute(<<~SQL.squish)
      ALTER DEFAULT PRIVILEGES FOR ROLE #{MIGRATOR} IN SCHEMA public
        GRANT USAGE, SELECT ON SEQUENCES TO #{APP}
    SQL
  end
end

namespace :db do
  namespace :privileges do
    desc "Apply table privileges from db/privileges.yml (run as healthos_migrator)"
    task :apply, [ :env ] => :environment do |_task, args|
      HealthosPrivileges.apply_to_env!(args[:env] || Rails.env)
    end

    desc "Apply table privileges to the test databases"
    task apply_test: :environment do
      HealthosPrivileges.apply_to_env!("test")
    end

    desc "Show effective app-role privileges per table"
    task check: :environment do
      conn = ActiveRecord::Base.connection
      rows = conn.select_all(<<~SQL.squish)
        SELECT c.relname AS table_name,
               has_table_privilege('#{HealthosPrivileges::APP}', c.oid, 'SELECT') AS sel,
               has_table_privilege('#{HealthosPrivileges::APP}', c.oid, 'INSERT') AS ins,
               has_table_privilege('#{HealthosPrivileges::APP}', c.oid, 'UPDATE') AS upd,
               has_table_privilege('#{HealthosPrivileges::APP}', c.oid, 'DELETE') AS del
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
        ORDER BY c.relname
      SQL

      if rows.count.zero?
        puts "no tables yet"
      else
        width = rows.map { |r| r["table_name"].length }.max
        puts format("%-#{width}s  %-6s %-6s %-6s %-6s", "TABLE", "SELECT", "INSERT", "UPDATE", "DELETE")
        rows.each do |r|
          puts format(
            "%-#{width}s  %-6s %-6s %-6s %-6s",
            r["table_name"],
            r["sel"] ? "y" : "-", r["ins"] ? "y" : "-",
            r["upd"] ? "y" : "-", r["del"] ? "y" : "-"
          )
        end
      end
    end
  end
end

# Privileges do not round-trip through structure.sql, so they must be
# re-applied after anything that creates or reloads the schema.
{
  "db:migrate"      => "db:privileges:apply",
  "db:schema:load"  => "db:privileges:apply",
  "db:test:prepare" => "db:privileges:apply_test"
}.each do |hooked, privilege_task|
  next unless Rake::Task.task_defined?(hooked)

  Rake::Task[hooked].enhance do
    Rake::Task[privilege_task].reenable
    Rake::Task[privilege_task].invoke
  end
end
