# frozen_string_literal: true

# Make the PostgreSQL client binaries discoverable in development and test.
#
# `config.active_record.schema_format = :sql` (ADR-002 Decision 3a) means Rails
# shells out to `pg_dump` and `psql` for every schema dump and load. On macOS,
# Homebrew's libpq is keg-only and therefore absent from PATH, which fails
# db:migrate with a bare "make sure pg_dump is installed" message.
#
# Prepending here rather than in bin/* means it works however Rails is invoked
# — bin/rails, bin/rake, an IDE task runner — instead of only through our
# wrapper scripts. It is also preferable to editing the developer's shell
# profile, which is not ours to change.
#
# pg_dump must be at least the server's major version, so this deliberately
# points at a specific keg rather than any pg_dump that happens to be around.
# On Linux and in CI the client comes from the distribution package and is
# already on PATH, so the guard simply does nothing.

if Rails.env.local?
  candidates = [
    "/opt/homebrew/opt/libpq/bin",   # Apple Silicon Homebrew
    "/usr/local/opt/libpq/bin"       # Intel Homebrew
  ]

  candidates.each do |dir|
    next unless File.directory?(dir)
    next if ENV["PATH"].to_s.split(File::PATH_SEPARATOR).include?(dir)

    ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
    break
  end
end
