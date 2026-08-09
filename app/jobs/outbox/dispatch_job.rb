# frozen_string_literal: true

module Outbox
  # Turns durable domain events into Active Jobs (HO §49).
  #
  # Delivery semantics are AT-LEAST-ONCE, deliberately. The enqueue targets
  # the queue database while the dispatched_at update targets the primary
  # (HO §6.3), so the two cannot share a transaction — the very dual-write
  # this outbox exists to survive. Given the choice, we enqueue first and mark
  # afterwards:
  #
  #   enqueue then mark  — a crash in between redelivers the event, so the
  #                        handler may run twice
  #   mark then enqueue  — a crash in between loses the event entirely
  #
  # Losing an event is unrecoverable; running a handler twice is something
  # S2C-020 already requires every job to tolerate. Hence this order.
  #
  # Concurrency: rows are claimed with FOR UPDATE SKIP LOCKED, so several
  # dispatchers can run without double-claiming or blocking each other.
  class DispatchJob < ApplicationJob
    queue_as :default

    DEFAULT_BATCH_SIZE = 100

    def perform(batch_size: DEFAULT_BATCH_SIZE)
      dispatched = 0
      failed = 0

      DomainEvent.transaction do
        events = DomainEvent.pending
          .limit(batch_size)
          .lock("FOR UPDATE SKIP LOCKED")
          .to_a

        events.each do |event|
          if dispatch(event)
            dispatched += 1
          else
            failed += 1
          end
        end
      end

      { dispatched: dispatched, failed: failed }
    end

    private

    def dispatch(event)
      job_class = Registry.job_for(event.event_type)

      # Only the event id crosses the job boundary. CLAUDE.md: "Pass IDs to
      # jobs, never payloads" — job arguments are serialized into the queue
      # database and appear in job introspection, so they must never carry
      # health data.
      job_class.perform_later(event.id)

      event.update!(dispatched_at: Time.current, last_error: nil)
      true
    rescue StandardError => e
      record_failure(event, e)
      false
    end

    # Failures must not roll back the surrounding batch, or one poisoned event
    # would block every other event behind it. The counter is bumped in its
    # own transaction so it survives independently.
    def record_failure(event, error)
      DomainEvent.connection.transaction(requires_new: true) do
        event.update_columns(
          attempts: event.attempts + 1,
          # Truncated: an exception message can be long, and it is written to
          # a tenant-facing table. Class plus a bounded message only — never
          # the payload (no PHI in error reports).
          last_error: "#{error.class}: #{error.message.to_s.truncate(500)}",
          updated_at: Time.current
        )
      end

      Rails.logger.warn(
        "[outbox] dispatch failed event_id=#{event.id} type=#{event.event_type} " \
        "attempts=#{event.attempts + 1} error=#{error.class}"
      )
    end
  end
end
