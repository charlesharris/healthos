# frozen_string_literal: true

module Definitions
  # HO §125: "CI compares current digest with recorded expected digest. If
  # code/config changed without version bump: FAIL. This prevents silent
  # reproducibility breakage."
  #
  # The lockfile is the recorded contract. Three failure modes, each meaning
  # something different:
  #
  #   CHANGED — a definition's content moved while its version stayed put.
  #             This is the one the gate exists for: every artifact already
  #             computed under that key@version now means something subtly
  #             different, and INV-6..12 are broken silently.
  #   REMOVED — a definition disappeared. Historical artifacts reference it
  #             forever, so removal makes them unreproducible.
  #   ADDED   — legitimate, but the lockfile must move in the same commit, or
  #             the recorded contract stops being authoritative.
  class Verifier
    LOCKFILE = Rails.root.join("config/definition_digests.yml")

    Result = Struct.new(:changed, :removed, :added, keyword_init: true) do
      def ok? = changed.empty? && removed.empty? && added.empty?
      def drift? = changed.any? || removed.any?
    end

    def self.call(...) = new(...).call

    def initialize(registry: Registry.instance, lockfile: LOCKFILE)
      @registry = registry
      @lockfile = lockfile
    end

    def call
      current = @registry.digest_manifest
      recorded = read_lockfile

      changed = current.filter_map do |key, digest|
        next unless recorded.key?(key)
        next if recorded[key] == digest

        { key: key, recorded: recorded[key], current: digest }
      end

      Result.new(
        changed: changed,
        removed: (recorded.keys - current.keys).sort,
        added: (current.keys - recorded.keys).sort
      )
    end

    def write_lockfile!
      content = {
        "generated_by" => "bin/definitions update",
        "note" => "Recorded digests for versioned definitions (HO §25, §125). " \
                  "Do not hand-edit. A changed digest for an existing key@version " \
                  "means a definition was modified without a version bump.",
        "digests" => @registry.digest_manifest
      }

      File.write(@lockfile, content.to_yaml)
      @registry.digest_manifest
    end

    def read_lockfile
      return {} unless File.exist?(@lockfile)

      (YAML.safe_load_file(@lockfile) || {}).fetch("digests", {})
    end
  end
end
