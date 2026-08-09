# frozen_string_literal: true

require "rails_helper"

# ADR-002 Decision 4b — the raw payload bucket as a genuine append-only log.
#
# Runs against real object storage rather than a double. The rest of the suite
# uses an in-memory stand-in, which proves the calling logic but cannot prove
# that object locking is actually configured — and object lock can only be
# enabled at bucket creation, so a mistake there is unrecoverable without
# recreating the bucket.
#
# Skipped when MinIO is not reachable, so `bin/test` still works without
# `docker compose up`. CI does not run MinIO today; this is a local and
# pre-deploy check. If it ever silently skips everywhere, the WORM guarantee
# is unverified — hence the explicit skip message.
RSpec.describe Storage::RawPayloadStore, type: :model do
  let(:store) { described_class.new }

  before do
    store.client.head_bucket(bucket: store.bucket)
  rescue StandardError => e
    skip "object storage unavailable (#{e.class}) — run `docker compose up -d minio` " \
         "and `docker compose run --rm minio_setup`"
  end

  it "round-trips a payload and verifies its hash" do
    payload = '{"systolic":142,"diastolic":88}'
    written = store.write(organization_id: SecureRandom.uuid, payload: payload)

    expect(written[:content_hash]).to eq(Digest::SHA256.hexdigest(payload))
    expect(store.read(object_key: written[:object_key], expected_hash: written[:content_hash]))
      .to eq(payload)
  end

  it "raises when the recorded hash does not match the stored bytes" do
    written = store.write(organization_id: SecureRandom.uuid, payload: '{"a":1}')

    expect {
      store.read(object_key: written[:object_key], expected_hash: Digest::SHA256.hexdigest("different"))
    }.to raise_error(described_class::IntegrityError)
  end

  it "content-addresses keys, so identical bytes reuse one object" do
    org = SecureRandom.uuid
    a = store.write(organization_id: org, payload: '{"same":1}')
    b = store.write(organization_id: org, payload: '{"same":1}')

    expect(a[:object_key]).to eq(b[:object_key])
  end

  it "separates objects by organization" do
    a = store.write(organization_id: SecureRandom.uuid, payload: '{"same":1}')
    b = store.write(organization_id: SecureRandom.uuid, payload: '{"same":1}')

    expect(a[:object_key]).not_to eq(b[:object_key])
  end

  # The guarantee that makes this a log rather than a bucket we promise not to
  # touch. Object lock cannot be enabled after creation, so if this fails the
  # bucket must be recreated — better to learn that here than at pilot.
  it "has object locking enabled on the raw payload bucket" do
    config = store.client.get_object_lock_configuration(bucket: store.bucket)

    expect(config.object_lock_configuration.object_lock_enabled).to eq("Enabled")
  rescue Aws::S3::Errors::ObjectLockConfigurationNotFoundError
    raise "Object locking is NOT enabled on #{store.bucket}. It can only be set at " \
          "bucket creation (ADR-002 4b) — recreate it with `mc mb --with-lock`."
  end
end
