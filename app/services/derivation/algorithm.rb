# frozen_string_literal: true

module Derivation
  # Base class for versioned derived-signal algorithms (INV-8).
  #
  # Key, version and digest are stamped onto every row produced. The digest is
  # computed from the algorithm's declared parameters — the same protection
  # HO §25 gives semantic definitions, catching a behaviour change made
  # without a version bump.
  #
  # An algorithm returns a value plus the exact inputs it consumed, so the
  # coordinator can record lineage (INV-3). It never writes rows itself, which
  # keeps it a pure function of its inputs and specable without a database.
  class Algorithm
    Outcome = Struct.new(
      :value_numeric, :value_text, :value_json, :unit,
      :inputs, :usable_input_count, :raw_input_count, :status,
      keyword_init: true
    ) do
      def computed? = status == "computed"
    end

    ALGORITHMS = {
      "daily_blood_pressure_summary" => "Hypertension::DailyBloodPressureSummary"
    }.freeze

    class << self
      def key = raise(NotImplementedError, "#{name} must define .key")
      def version = raise(NotImplementedError, "#{name} must define .version")

      # Parameters that affect the result. Anything here becomes part of the
      # digest, so changing a minimum or a rounding rule without bumping the
      # version is detectable rather than silent.
      def parameters = {}

      def digest
        Definitions::DefinitionDigest.compute(
          key: key, version: version, parameters: parameters
        )
      end

      def find(algorithm_key)
        name = ALGORITHMS[algorithm_key.to_s]
        raise ArgumentError, "no algorithm registered for #{algorithm_key.inspect}" if name.blank?

        name.constantize
      end
    end

    def call = raise(NotImplementedError)
  end
end
