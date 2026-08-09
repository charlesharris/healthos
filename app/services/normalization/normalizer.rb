# frozen_string_literal: true

module Normalization
  # Base class for versioned normalizers (INV-6: normalizers are versioned).
  #
  # A normalizer turns one RawEnvelope into canonical telemetry. Its key and
  # version are stamped onto every row it produces, so any canonical value can
  # name the exact code that produced it — and re-running a NEW version
  # produces new rows alongside the old rather than rewriting them (HO §155).
  #
  # Behaviour change means a new version. Never edit `version` in place while
  # changing what the normalizer does: every observation already stamped with
  # that version would silently mean something else.
  class Normalizer
    class InvalidPayload < StandardError; end

    # A normalizer returns intents rather than writing rows itself, so the
    # coordinator owns the transaction and idempotency. That also makes a
    # normalizer a pure function of its payload, which is what lets specs
    # exercise mapping logic without touching the database.
    ObservationIntent = Struct.new(
      :semantic_key, :semantic_version, :value_numeric, :value_text, :value_code,
      :unit, :observed_at, :quality_state, :recording_method, :measurement_protocol,
      :timezone_offset_minutes, :quality_flags,
      keyword_init: true
    )

    GroupIntent = Struct.new(:semantic_key, :semantic_version, :observed_at, :observations,
                             keyword_init: true)

    Result = Struct.new(:groups, :observations, :subject_identifier, keyword_init: true)

    # Adapter key → normalizer class name.
    #
    # An explicit map, resolved lazily, rather than self-registration at file
    # load. Under Zeitwerk a class that nothing has referenced yet has not been
    # loaded, so a registry populated by load-time side effects is empty until
    # something happens to touch the file — which makes behaviour depend on
    # autoload order. Same reasoning as Outbox::Registry.
    ADAPTERS = {
      "synthetic_bp_json" => "Normalization::SyntheticBloodPressureJson"
    }.freeze

    class << self
      def key = raise(NotImplementedError, "#{name} must define .key")
      def version = raise(NotImplementedError, "#{name} must define .version")

      def for_adapter(adapter_key)
        name = ADAPTERS[adapter_key.to_s]
        raise ArgumentError, "no normalizer registered for adapter #{adapter_key.inspect}" if name.blank?

        name.constantize
      end

      def adapter_keys = ADAPTERS.keys
    end

    def initialize(envelope:, payload:)
      @envelope = envelope
      @payload = payload
    end

    attr_reader :envelope, :payload

    def call = raise(NotImplementedError)

    def key = self.class.key
    def version = self.class.version
  end
end
