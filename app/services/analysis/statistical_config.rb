# frozen_string_literal: true

module Analysis
  # Reader for the governed statistical configuration (STAT-044).
  #
  # Every threshold the Statistical Contract specifies lives in
  # `config/statistics/*.yml` and is read through here. Nothing else in the
  # codebase may hard-code one.
  #
  # The point is reviewability. A threshold buried in a service is a threshold
  # nobody reviews, and CLAUDE.md is explicit: "never 'fix' a statistical
  # threshold, gate, or evidence rule to make a test pass — those changes
  # require a version bump and human review." Keeping them in one governed
  # file means a diff touching statistics is visible as such.
  #
  # Frozen on load, so nothing can mutate a threshold at runtime.
  class StatisticalConfig
    class UnknownSetting < StandardError; end

    PATH = Rails.root.join("config/statistics")

    class << self
      def instance
        @instance ||= new
      end

      def reload! = @instance = new

      delegate :fetch, :baseline, :affected_window, :single_episode, :digest, to: :instance
    end

    def initialize
      @data = PATH.glob("*.yml").sort.each_with_object({}) do |file, out|
        out[file.basename(".yml").to_s] = deep_freeze(YAML.safe_load_file(file))
      end.freeze
    end

    def fetch(file, *path)
      node = @data.fetch(file.to_s) { raise UnknownSetting, "no statistical config file #{file}" }

      path.reduce(node) do |current, key|
        raise UnknownSetting, "#{file}.#{path.join('.')} is not configured" unless current.is_a?(Hash)

        current.fetch(key.to_s) { raise UnknownSetting, "#{file}.#{path.join('.')} is not configured" }
      end
    end

    def baseline(key) = fetch("baseline_thresholds", "baseline", key)
    def affected_window(key) = fetch("baseline_thresholds", "affected_window", key)
    def single_episode(key) = fetch("baseline_thresholds", "single_episode", key)

    # Included in artifact version tuples, so an artifact records which
    # governed configuration it was computed under (HO §80). A threshold
    # change is then visible in the artifact rather than only in git history.
    def digest
      @digest ||= Definitions::DefinitionDigest.compute(@data)
    end

    private

    # DEEP freeze, not shallow. `Hash#freeze` leaves nested hashes mutable, so
    # a shallow freeze would let any caller reach in and change a governed
    # threshold at runtime — and a threshold that can be mutated in process is
    # not governed, whatever the file says. Caught by spec rather than review.
    def deep_freeze(value)
      case value
      when Hash then value.transform_values { |v| deep_freeze(v) }.freeze
      when Array then value.map { |v| deep_freeze(v) }.freeze
      else value.freeze
      end
    end
  end
end
