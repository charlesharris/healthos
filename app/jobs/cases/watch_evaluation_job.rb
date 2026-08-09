# frozen_string_literal: true

module Cases
  # The periodic sweep behind HO §45's watch conditions (epic 002-19).
  #
  # A thin wrapper, as every job here is: the decision of what "due" means
  # lives in WatchCondition#satisfied_by? and the acting-on-it lives in
  # EvaluateWatchConditions, so this class only decides which Cases are worth
  # looking at.
  #
  # Deliberately NOT scheduled per-Case at watch-creation time. A
  # `perform_later(wait_until: expires_at)` would be cheaper, but it loses
  # every condition that is not a timer (new_observation_count, new_signal
  # have no due date), and a queue restart or a job pruned as stale would drop
  # the wakeup silently. A sweep re-derives what is due from the database
  # every run, so nothing is lost by a queue that forgot.
  class WatchEvaluationJob < ApplicationJob
    queue_as :default

    # Evaluated in id batches rather than one query so a large organization's
    # backlog cannot hold a single long transaction open — each Case commits
    # on its own, and a failure part-way through leaves the rest evaluated.
    BATCH_SIZE = 200

    def perform
      fired = 0

      due_case_ids.each_slice(BATCH_SIZE) do |ids|
        CaseRecord.where(id: ids).find_each do |case_record|
          fired += EvaluateWatchConditions.call(case_record: case_record).size
        rescue StandardError => e
          # One organization's bad Case must not stop every other
          # organization's watches from firing. Ids only — no PHI in logs.
          Rails.logger.error(
            "[watch_evaluation] case_id=#{case_record.id} failed: #{e.class}: #{e.message}"
          )
        end
      end

      Rails.logger.info("[watch_evaluation] conditions_fired=#{fired}")
      fired
    end

    private

    # Cross-organization by design: this is platform housekeeping, not a
    # provider-facing query, and skipping quiet organizations is exactly how
    # a watch would go unfired. The org scoping that matters — every row
    # carrying organization_id, every provider query passing an authorized
    # context — is unaffected; nothing here is exposed to a user.
    #
    # `expires_at` cannot filter here: only time_elapsed has one. The
    # predicate is per-type and lives on the model, so this narrows to Cases
    # with any pending condition and lets the model decide.
    def due_case_ids
      WatchCondition
        .pending
        .joins(:case_record)
        .where(cases: { status: CaseRecord::ACTIVE_STATUSES })
        .distinct
        .pluck(:case_id)
    end
  end
end
