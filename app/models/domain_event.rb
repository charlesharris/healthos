# frozen_string_literal: true

# A durable record of something that happened, written in the same transaction
# as the state change that caused it (HO §48, §49; S2C-021).
#
# The row is the intent to dispatch. Turning it into an Active Job is a
# separate, later, retryable step — see Outbox::DispatchJob.
class DomainEvent < ApplicationRecord
  # Events give up after this many failed dispatch attempts and stop being
  # selected, rather than spinning forever and starving newer events. They
  # remain visible for support (HO §157) — nothing is deleted.
  MAX_ATTEMPTS = 10

  belongs_to :organization

  validates :aggregate_type, :aggregate_id, :event_type, :occurred_at, presence: true

  # Ordered by (occurred_at, id) to match index_domain_events_pending. id is
  # UUIDv7 and therefore time-ordered, so it breaks ties in creation order
  # rather than arbitrarily (ADR-002 Decision 3b).
  scope :pending, lambda {
    where(dispatched_at: nil)
      .where(attempts: ...MAX_ATTEMPTS)
      .order(:occurred_at, :id)
  }

  scope :dead, -> { where(dispatched_at: nil).where(attempts: MAX_ATTEMPTS..) }
  scope :dispatched, -> { where.not(dispatched_at: nil) }

  def dispatched? = dispatched_at.present?
  def dead? = !dispatched? && attempts >= MAX_ATTEMPTS
end
