# frozen_string_literal: true

module Cases
  # Thin wrapper (CLAUDE.md). Retry-safe because CorrelateSignal is idempotent
  # on the CaseSignal uniqueness constraint (S2C-020).
  class CorrelateSignalJob < ApplicationJob
    queue_as :default

    def perform(domain_event_id)
      event = DomainEvent.find(domain_event_id)
      signal = Monitoring::Signal.find(event.payload.fetch("signal_id"))

      CorrelateSignal.call(signal: signal)
    end
  end
end
