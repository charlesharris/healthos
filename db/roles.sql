-- Database roles for the append-only enforcement model.
-- ADR-002 Decision 4a. See docs/architecture/decisions/ADR-002-*.md.
--
-- Roles are cluster-level objects, so they cannot come from a Rails migration.
-- This file runs from docker-entrypoint-initdb.d on first initialisation of an
-- empty Postgres volume, and is re-applied idempotently by bin/setup. In a
-- managed environment it is a runbook step executed by the master role.
--
-- Per-database and per-table privileges are NOT here — they live in
-- db/privileges.yml and are reconciled by `bin/rails db:privileges:apply`
-- (Decision 4a-v), because privileges cannot round-trip through structure.sql.
--
-- The passwords below are development-only. Production supplies them through
-- managed secrets (HO §6.6).

-- healthos_migrator — owns the schema, runs migrations.
-- CREATEDB so `bin/rails db:create` works as this role.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'healthos_migrator') THEN
    CREATE ROLE healthos_migrator LOGIN PASSWORD 'healthos_dev_password' CREATEDB;
  END IF;
END
$$;

-- healthos_app — the Rails runtime, console and test suite.
-- Deliberately NOT a member of healthos_migrator: role membership would let it
-- inherit the owner's privileges and silently defeat the entire scheme.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'healthos_app') THEN
    CREATE ROLE healthos_app LOGIN PASSWORD 'healthos_dev_password';
  END IF;
END
$$;

-- healthos_admin — retention and support operations that the app role cannot
-- perform, chiefly DELETE on append-only tables (ADR-002 Decision 4a-iii:
-- monitor_evaluations retention per HO §32, superseded-artifact collection per
-- HO §155). Support access must itself be audited (HO §157).
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'healthos_admin') THEN
    CREATE ROLE healthos_admin LOGIN PASSWORD 'healthos_dev_password';
  END IF;
END
$$;
