# frozen_string_literal: true

module Cases
  # The authoritative Case workflow history (HO §39, S2C-010, INV-26).
  #
  # Append-only and hash-chained (ADR-002 4c): each row carries the digest of
  # the previous one, so a mutation is detectable even by an actor who can
  # bypass the grants. Low volume, high scrutiny — the chain's serialization
  # cost is acceptable here and would not be on observations.
  class CaseEvent < ApplicationRecord
    belongs_to :organization
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id, inverse_of: :case_events

    validates :event_type, :occurred_at, presence: true

    before_create :chain_hash

    def readonly? = persisted?

    def self.append!(case_record:, event_type:, payload: {}, actor_type: "system", actor_id: nil,
                     occurred_at: Time.current)
      create!(
        organization_id: case_record.organization_id, case_record: case_record,
        event_type: event_type, payload: payload,
        actor_type: actor_type, actor_id: actor_id, occurred_at: occurred_at
      )
    end

    # Verifies the chain for one Case. Support tooling calls this; a break
    # means the timeline was altered outside the application.
    def self.chain_intact?(case_record)
      previous = nil

      where(case_id: case_record.id).order(:occurred_at, :id).each do |event|
        return false unless event.prev_hash == previous
        return false unless event.row_hash == event.compute_hash(previous)

        previous = event.row_hash
      end

      true
    end

    # Must produce the same digest before and after the database round trip,
    # or the chain reports itself broken forever — which is worse than having
    # no chain, since it makes real tampering indistinguishable from noise.
    #
    # Two things break naive hashing here:
    #
    #   payload      JSONB does not preserve key order, so `to_json` differs
    #                between the in-memory hash and the reloaded one.
    #                Canonicalized (keys sorted) instead.
    #   occurred_at  PostgreSQL timestamp(6) TRUNCATES to microseconds while
    #                Ruby's iso8601(6) ROUNDS, so a nanosecond-precision Time
    #                hashes differently after reload. %6N truncates, matching
    #                the column.
    def compute_hash(previous)
      Digest::SHA256.hexdigest(
        [
          previous, case_id, event_type, actor_type, actor_id,
          occurred_at.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N"),
          Definitions::DefinitionDigest.canonical_json(payload)
        ].join("|")
      )
    end

    private

    def chain_hash
      self.prev_hash = self.class.where(case_id: case_id).order(:occurred_at, :id).last&.row_hash
      self.row_hash = compute_hash(prev_hash)
    end
  end
end
