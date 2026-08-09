# frozen_string_literal: true

module Definitions
  # A versioned semantic definition (HO §23).
  #
  # Immutable by version: "behavior change means new version." The registry
  # freezes every instance, and `bin/definitions verify` fails CI if content
  # changes while key and version stay the same (HO §25, §125).
  class SemanticDefinition
    KINDS = %w[vital measurement derived event interval].freeze
    VALUE_TYPES = %w[numeric integer boolean categorical text datetime].freeze

    # HO §23 requires a privacy classification on every definition, and
    # PD §57 requires high-cardinality analytical dimensions to inherit it.
    PRIVACY_CLASSES = %w[phi operational derived_non_identifying].freeze

    ATTRIBUTES = %i[
      key version kind value_type unit privacy_class
      aggregation semantic_family source_family derivation_family
      expected_measurement description
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(attrs)
      attrs = attrs.transform_keys(&:to_sym)

      @key = attrs.fetch(:key)
      @version = Integer(attrs.fetch(:version))
      @kind = attrs.fetch(:kind).to_s
      @value_type = attrs.fetch(:value_type).to_s
      @unit = attrs[:unit]
      @privacy_class = attrs.fetch(:privacy_class).to_s
      @aggregation = attrs[:aggregation]
      # SC §49–50 difference families. Carried on the definition so that
      # correlated-family suppression never needs a schema change later.
      @semantic_family = attrs[:semantic_family]
      @source_family = attrs[:source_family]
      @derivation_family = attrs[:derivation_family]
      @expected_measurement = attrs[:expected_measurement]
      @description = attrs[:description]

      validate!
      @content = attrs
      # Computed before freezing: memoizing later would mutate a frozen
      # object. Eager is right anyway — a definition that cannot be digested
      # should fail at load, not at first use.
      @digest = DefinitionDigest.compute(@content)
      freeze
    end

    attr_reader :digest

    # HO §25: records store semantic_key + semantic_version; artifacts also
    # store the digest.
    def identity = { key: key, version: version, digest: digest }

    def versioned_key = "#{key}@v#{version}"

    def phi? = privacy_class == "phi"

    private

    def validate!
      raise ArgumentError, "key is required" if key.blank?
      raise ArgumentError, "version must be positive" unless version.positive?
      raise ArgumentError, "unknown kind #{kind.inspect}" unless KINDS.include?(kind)
      raise ArgumentError, "unknown value_type #{value_type.inspect}" unless VALUE_TYPES.include?(value_type)
      raise ArgumentError, "unknown privacy_class #{privacy_class.inspect}" unless PRIVACY_CLASSES.include?(privacy_class)

      return unless value_type == "numeric" && unit.blank?

      # A numeric value without a unit is uninterpretable, and unit confusion
      # is a classic source of silent clinical error.
      raise ArgumentError, "#{key} is numeric and must declare a unit"
    end
  end
end
