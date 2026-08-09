# frozen_string_literal: true

module Definitions
  # HO §25: "digest is generated from normalized definition/config content."
  #
  # Normalization is the whole point. A digest over raw text would change when
  # someone reindents a YAML file, and CI would then demand a version bump for
  # a whitespace edit — which trains people to bump versions reflexively,
  # destroying the signal. So the digest is computed over the *semantic*
  # content: keys sorted, values canonicalized, formatting discarded.
  module DefinitionDigest
    module_function

    def compute(content)
      Digest::SHA256.hexdigest(canonical_json(content))
    end

    # Deterministic across Ruby versions and hash insertion order.
    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, out|
          raw = value.key?(key) ? value[key] : value[key.to_sym]
          out[key] = canonicalize(raw)
        end
      when Array
        # Order is preserved: for a list of allowed values or a pipeline of
        # rules, order can be semantically meaningful.
        value.map { |v| canonicalize(v) }
      when Symbol
        value.to_s
      when Float
        # 1.0 and 1 must not digest differently just because YAML happened to
        # parse one as a float.
        value == value.to_i ? value.to_i : value
      else
        value
      end
    end
  end
end
