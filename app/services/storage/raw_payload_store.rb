# frozen_string_literal: true

module Storage
  # Object storage for raw source payloads (HO §6.5; ADR-002 Decision 4b).
  #
  # The relational database stores keys and hashes; the bytes live here, in a
  # bucket with object locking enabled. Object lock is what makes raw source
  # truth genuinely append-only rather than merely policy-append-only: in
  # compliance mode not even the account root can delete an object before its
  # retention expires. That is a stronger guarantee than a streaming log,
  # which always has an admin API (see ADR-001 §4).
  #
  # Content hashes are verified on READ, not only computed on write. A hash
  # written and never checked proves nothing; verifying on read is what makes
  # tampering with either the object store or the database row detectable.
  class RawPayloadStore
    class IntegrityError < StandardError; end

    DEFAULT_BUCKET = "healthos-raw-payloads"

    class << self
      def instance = @instance ||= new

      # A seam, used by specs that drive code which reaches for the store
      # itself rather than accepting one (the demo seed, notably).
      #
      # The unit suite deliberately runs without object storage: the real
      # MinIO round trip is exercised by the ingestion integrity specs and by
      # `bin/smoke`, and making every developer run a bucket to test a
      # statistical question puts an unrelated dependency in the way. Callers
      # that CAN take a store injected should keep doing that — this is for
      # the ones that cannot.
      attr_writer :instance

      def reset_instance! = @instance = nil
    end

    def initialize(bucket: nil, client: nil)
      @bucket = bucket || ENV.fetch("HEALTHOS_RAW_BUCKET", DEFAULT_BUCKET)
      @client = client
    end

    attr_reader :bucket

    def client
      @client ||= begin
        require "aws-sdk-s3"
        Aws::S3::Client.new(
          endpoint: ENV.fetch("HEALTHOS_S3_ENDPOINT", "http://localhost:9000"),
          access_key_id: ENV.fetch("HEALTHOS_S3_ACCESS_KEY", "healthos"),
          secret_access_key: ENV.fetch("HEALTHOS_S3_SECRET_KEY", "healthos_dev_password"),
          region: ENV.fetch("HEALTHOS_S3_REGION", "us-east-1"),
          force_path_style: true
        )
      end
    end

    def self.digest(payload) = Digest::SHA256.hexdigest(payload)

    # Keys are content-addressed within an organization. Storing the same
    # bytes twice therefore lands on the same key, which keeps a retried
    # ingestion from creating a second object.
    def self.key_for(organization_id:, content_hash:)
      "org/#{organization_id}/raw/#{content_hash[0, 2]}/#{content_hash}"
    end

    def write(organization_id:, payload:, content_type: "application/json")
      hash = self.class.digest(payload)
      key = self.class.key_for(organization_id: organization_id, content_hash: hash)

      client.put_object(bucket: bucket, key: key, body: payload, content_type: content_type)

      { object_key: key, content_hash: hash }
    end

    # Reads and verifies. Raises rather than returning suspect bytes — a
    # provenance drilldown that silently shows altered evidence would be worse
    # than one that fails (INV-4, INV-5, HO §131).
    def read(object_key:, expected_hash:)
      payload = client.get_object(bucket: bucket, key: object_key).body.read
      actual = self.class.digest(payload)

      unless ActiveSupport::SecurityUtils.secure_compare(actual, expected_hash)
        raise IntegrityError,
          "payload at #{object_key} does not match its recorded hash " \
          "(expected #{expected_hash[0, 12]}…, got #{actual[0, 12]}…)"
      end

      payload
    end

    def exists?(object_key:)
      client.head_object(bucket: bucket, key: object_key)
      true
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      false
    end
  end
end
