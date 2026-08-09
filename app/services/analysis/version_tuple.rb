# frozen_string_literal: true

module Analysis
  # HO §80 / PD §13: the full reproducibility tuple.
  #
  # Every analytical artifact records which versions produced it, so
  # "reproduce this Finding" is answerable years later without archaeology
  # (INV-6..14). Stored ON the artifact rather than joined at read time,
  # because a join would resolve to today's versions and quietly rewrite
  # history.
  #
  # Includes the governed statistical config digest: a threshold change is
  # then visible in the artifact itself, not only in git history.
  module VersionTuple
    module_function

    def build(definition: nil, extra: {})
      {
        "definition" => definition && {
          "key" => definition.key,
          "version" => definition.version,
          "digest" => definition.digest
        },
        "statistical_config_digest" => StatisticalConfig.instance.digest,
        "semantic_registry_digest" => semantic_registry_digest,
        "computed_at" => Time.current.utc.iso8601
      }.compact.merge(extra.stringify_keys)
    end

    # One digest over every semantic definition in play, so an artifact can
    # prove which registry it was computed against.
    def semantic_registry_digest
      Definitions::DefinitionDigest.compute(Definitions::Registry.digest_manifest)
    end
  end
end
