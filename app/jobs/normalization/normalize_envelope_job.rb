# frozen_string_literal: true

module Normalization
  # Thin wrapper around the service (CLAUDE.md: "jobs are thin wrappers around
  # services"). All logic, and all idempotency, live in NormalizeEnvelope.
  #
  # Takes the domain event id rather than a payload — CLAUDE.md forbids
  # payloads in job arguments, and job arguments are serialized into the queue
  # database where they would outlive the request.
  class NormalizeEnvelopeJob < ApplicationJob
    queue_as :default

    # Retry-safe by construction (S2C-020): the service is idempotent on
    # RawEnvelope + normalizer version.
    retry_on Storage::RawPayloadStore::IntegrityError, wait: :polynomially_longer, attempts: 3

    def perform(domain_event_id)
      event = DomainEvent.find(domain_event_id)
      envelope = RawEnvelope.find(event.payload.fetch("raw_envelope_id"))

      NormalizeEnvelope.call(envelope: envelope)
    end
  end
end
