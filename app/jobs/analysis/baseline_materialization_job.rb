# frozen_string_literal: true

module Analysis
  # Materializes cohort baselines for one organization and measure.
  #
  # A thin wrapper, as every job here is: the decision of what a baseline IS
  # lives in the BaselineDefinition, and materializing one lives in
  # Baselines::Materialize.
  #
  # IDs, never payloads (CLAUDE.md): the arguments are an organization id, a
  # semantic key and an instant, all of which are safe to sit in the queue
  # database where they outlive the request.
  #
  # Retry-safe because Materialize is idempotent on artifact identity — a job
  # that dies halfway and runs again redoes only the subjects it had not
  # reached, and never produces a duplicate artifact.
  class BaselineMaterializationJob < ApplicationJob
    queue_as :default

    def perform(organization_id:, semantic_key:, as_of: nil)
      organization = Organization.find(organization_id)
      instant = as_of ? Time.zone.parse(as_of.to_s) : Time.current

      outcome = Baselines::MaterializeCohort.call(
        organization: organization, semantic_key: semantic_key, as_of: instant
      )

      # No PHI: counts, a key and an instant. Enough to tell a partial run
      # from a complete one, which is the question asked of this log.
      Rails.logger.info(
        "[baselines] organization_id=#{organization_id} semantic_key=#{semantic_key} " \
        "as_of=#{instant.utc.iso8601} created=#{outcome.created} existing=#{outcome.existing} " \
        "skipped=#{outcome.skipped}"
      )

      outcome
    end
  end
end
