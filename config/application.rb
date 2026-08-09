require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Healthos
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # ADR-002 Decision 3a. `schema.rb` cannot represent CHECK constraints,
    # partial indexes, or (later) partitions — all of which HO §112 requires
    # us to use aggressively. Set before the first migration exists; changing
    # it afterwards produces a painful diff.
    #
    # Note that privileges do NOT round-trip through this file:
    # ActiveRecord's PostgreSQLDatabaseTasks#structure_dump hard-codes
    # `--no-privileges`. Grants are applied separately by
    # `db:privileges:apply` (ADR-002 Decision 4a-v).
    config.active_record.schema_format = :sql

    # ADR-002 Decision 3b. Time-ordered UUIDv7 rather than random UUIDv4:
    # random keys cause index write amplification on append-heavy tables and
    # destroy the physical time-ordering that BRIN would need if the
    # partitioning tripwires (ADR-001 T2/T7/T8) ever fire.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.system_tests = nil
    end

    # Domain pack subdirectories (semantics/, derived_signals/, monitors/,
    # cases/, contexts/, baselines/, comparisons/) are organizational
    # categories from HO §24, not namespaces. Collapsing them means a pack's
    # code reads as Hypertension::DailyBloodPressureSummary rather than
    # Hypertension::DerivedSignals::DailyBloodPressureSummary, which keeps the
    # domain vocabulary flat and matches how the handover talks about it.
    Rails.autoloaders.main.collapse("#{root}/app/domain_packs/*/*")

    # All times are stored and reasoned about in UTC. Subject-local time is a
    # display and analysis concern derived from `subjects.timezone`
    # (epic 001-04), never an ambient default — HO §121 calls out timezone
    # boundaries as a statistical regression case.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
  end
end
