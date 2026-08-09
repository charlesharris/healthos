# frozen_string_literal: true

module Definitions
  # Runtime registry of versioned definitions (HO §23).
  #
  # Definitions live in code and YAML, not in a user-editable database — HO
  # §23 is explicit ("do not begin with a user-editable semantic-definition
  # database") and HO §168 gives the reasoning: code review governs behaviour,
  # reproducibility stays easy, and users cannot author algorithms.
  #
  # Several versions of a key coexist. Historical artifacts reference the
  # version they were computed under, so an old Comparison stays reproducible
  # after a definition is revised (INV-6..12).
  class Registry
    class UnknownDefinition < StandardError; end
    class DuplicateDefinition < StandardError; end

    CORE_PATH = Rails.root.join("config/semantics")
    DOMAIN_PACK_PATH = Rails.root.join("app/domain_packs")

    class << self
      def instance
        @instance ||= load!
      end

      def reload! = @instance = load!

      delegate :fetch, :find, :all, :keys, :digest_manifest, to: :instance

      private

      def load!
        new(source_files)
      end

      def source_files
        CORE_PATH.glob("**/*.yml").sort + DOMAIN_PACK_PATH.glob("*/semantics/**/*.yml").sort
      end
    end

    def initialize(files)
      @definitions = {}

      files.each { |file| load_file(file) }

      @definitions.freeze
    end

    # Latest version of a key.
    def find(key)
      versions = @definitions[key.to_s]
      return nil if versions.blank?

      versions[versions.keys.max]
    end

    # A specific version — what artifacts resolve against, so that a historical
    # artifact keeps meaning the same thing forever.
    def fetch(key, version: nil)
      versions = @definitions[key.to_s]
      raise UnknownDefinition, "no semantic definition for #{key.inspect}" if versions.blank?

      if version.nil?
        versions[versions.keys.max]
      else
        versions.fetch(Integer(version)) do
          raise UnknownDefinition, "#{key} has no version #{version}"
        end
      end
    end

    def all = @definitions.values.flat_map(&:values)
    def keys = @definitions.keys.sort

    # Consumed by `bin/definitions verify` and its CI gate. Sorted so the
    # manifest is stable regardless of file ordering.
    def digest_manifest
      all.sort_by(&:versioned_key).to_h { |d| [ d.versioned_key, d.digest ] }
    end

    private

    def load_file(path)
      data = YAML.safe_load_file(path, permitted_classes: [], aliases: true) || {}

      Array(data["definitions"]).each do |raw|
        definition = SemanticDefinition.new(raw)
        bucket = (@definitions[definition.key] ||= {})

        if bucket.key?(definition.version)
          raise DuplicateDefinition,
            "#{definition.versioned_key} is defined twice (second in #{path})"
        end

        bucket[definition.version] = definition
      end
    end
  end
end
