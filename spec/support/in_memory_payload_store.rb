# frozen_string_literal: true

# An in-memory stand-in for object storage, with the same interface as
# Storage::RawPayloadStore.
#
# The bulk of the suite must not need a running bucket. The real MinIO round
# trip is covered where it matters — spec/ingestion/raw_envelope_spec.rb for
# integrity behaviour, and bin/smoke for the full boot — so nothing here
# substitutes for exercising the real store, it just keeps the unit suite from
# depending on a container being up.
#
# Content addressing and hash verification are reproduced faithfully rather
# than stubbed away: a fake that always returned the bytes it was given would
# make the integrity checks in Ingestion and Normalization untestable.
class InMemoryPayloadStore
  attr_reader :objects

  def initialize = @objects = {}

  def write(organization_id:, payload:, content_type: "application/json")
    hash = Storage::RawPayloadStore.digest(payload)
    key = Storage::RawPayloadStore.key_for(organization_id: organization_id, content_hash: hash)
    @objects[key] = payload
    { object_key: key, content_hash: hash, content_type: content_type }
  end

  def read(object_key:, expected_hash:)
    payload = @objects.fetch(object_key)
    actual = Storage::RawPayloadStore.digest(payload)
    raise Storage::RawPayloadStore::IntegrityError, "mismatch" unless actual == expected_hash

    payload
  end
end
