# frozen_string_literal: true

module Analysis
  # Base class for versioned Context definitions (HO §51, INV-9).
  #
  # A ContextDefinition says WHICH dimensions describe a subject over a
  # window. It does not compute effects, judge evidence, or compare anything —
  # it produces the raw material a Comparison later reasons about.
  #
  # HO §10 in the product doc puts it well: "Context is constructed, not
  # canonical." A Context is one defensible view of a subject at an instant,
  # and different definitions can legitimately describe the same subject
  # differently. That is why the definition key, version and digest travel on
  # every Context — without them "what did we think was true" is unanswerable
  # later.
  class ContextDefinition
    # A dimension the definition emits. Families come from the semantic
    # registry rather than being restated here, so there is one place where a
    # dimension's family is declared (SC §49–50, STAT-031).
    Dimension = Struct.new(
      :key, :version, :value_numeric, :value_text, :value_boolean, :value_json,
      :unit, :quality_state, :window, :evidence, :details,
      :semantic_family, :source_family, :derivation_family, keyword_init: true
    ) do
      def observed? = quality_state.nil? || quality_state == "observed"
    end

    Materialization = Struct.new(:dimensions, :status, :inputs, :data_completeness,
                                 keyword_init: true)

    DEFINITIONS = {
      "blood_pressure_change" => "Hypertension::BloodPressureChangeContext"
    }.freeze

    class << self
      def key = raise(NotImplementedError, "#{name} must define .key")
      def version = raise(NotImplementedError, "#{name} must define .version")

      # Parameters that affect the output. Digested, so a behaviour change
      # without a version bump is detectable (HO §25).
      def parameters = {}

      def digest
        Definitions::DefinitionDigest.compute(key: key, version: version, parameters: parameters)
      end

      def find(definition_key)
        name = DEFINITIONS[definition_key.to_s]
        raise ArgumentError, "no context definition for #{definition_key.inspect}" if name.blank?

        name.constantize
      end

      # Every biological key the registered packs declare, in the order they
      # declare it.
      #
      # Exists so a cohort surface with no Case in hand — and therefore no
      # context definition to consult — can still open on the measure a pack
      # considers primary, instead of whichever key wins an alphabetical tie.
      # Platform core asks the packs rather than naming a key (INV-35).
      def declared_key_order
        DEFINITIONS.keys.flat_map do |definition_key|
          Array(find(definition_key).parameters[:biological_keys])
        end.uniq
      end
    end

    def initialize(subject:, window:, as_of:)
      @subject = subject
      @window = window
      @as_of = as_of
    end

    attr_reader :subject, :window, :as_of

    def materialize = raise(NotImplementedError)

    protected

    # Families are read from the semantic registry so a dimension's family is
    # declared in exactly one place. A definition restating them would let the
    # two drift, and STAT-033's suppression would then be reasoning about
    # families that no longer match the data.
    def families_for(semantic_key)
      definition = Definitions::Registry.find(semantic_key)
      return {} if definition.nil?

      {
        semantic_family: definition.semantic_family,
        source_family: definition.source_family,
        derivation_family: definition.derivation_family
      }
    end
  end
end
