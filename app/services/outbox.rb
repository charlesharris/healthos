# frozen_string_literal: true

# The transactional outbox (HO §49, S2C-021).
#
# `Outbox.publish` is the helper epic 001-03 asks for: "insert domain_event
# inside the same transaction as the state change". Callers use it like this,
# matching the HO §48 transaction boundaries:
#
#   ActiveRecord::Base.transaction do
#     signal = Signal.create!(...)
#     Outbox.publish(
#       organization: signal.organization,
#       aggregate: signal,
#       event_type: "monitoring.signal_created"
#     )
#   end
#
# External network calls must NOT happen here or anywhere else inside the
# transaction (S2C-024) — that is the dispatcher's job, after commit.
module Outbox
  class NotInTransactionError < StandardError; end

  # Event types are enumerated rather than free-form so that a typo is a load
  # error instead of an event nothing is listening for. Names follow the
  # HO §49 examples.
  EVENT_TYPES = %w[
    telemetry.observation_created
    monitoring.signal_created
    cases.case_created
    cases.signal_attached
    cases.case_analysis_requested
    cases.case_resolved
  ].freeze

  class UnknownEventType < ArgumentError; end

  module_function

  def publish(organization:, aggregate:, event_type:, payload: {}, occurred_at: Time.current)
    unless EVENT_TYPES.include?(event_type)
      raise UnknownEventType, "#{event_type.inspect} is not a registered event type"
    end

    ensure_in_transaction!

    DomainEvent.create!(
      organization: organization,
      aggregate_type: aggregate.class.name,
      aggregate_id: aggregate.id,
      event_type: event_type,
      payload: payload,
      occurred_at: occurred_at
    )
  end

  # The entire value of the outbox is that the event commits atomically with
  # the state change. Publishing outside a transaction still writes a row, but
  # silently provides none of that guarantee, so it is refused.
  #
  # Note for readers of the specs: with transactional fixtures every example
  # already runs inside a transaction, so this guard is trivially satisfied
  # there. It is covered by an example that turns transactional fixtures off.
  def ensure_in_transaction!
    return if DomainEvent.connection.transaction_open?

    raise NotInTransactionError,
      "Outbox.publish must be called inside a transaction (S2C-021); " \
      "otherwise the event and the state change can diverge"
  end
end
