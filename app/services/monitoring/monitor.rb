# frozen_string_literal: true

module Monitoring
  # Base class for versioned monitors (HO §30).
  #
  # A monitor reads canonical and derived state, evaluates a versioned
  # condition, and produces zero or more immutable Signals.
  #
  # It does NOT create Cases (S2C-003). That boundary is the difference
  # between an observability product and an alert manager: machine evidence
  # accumulates freely, and the decision that a human should look at something
  # is made separately, by correlation. A spec asserts monitors never touch
  # Case tables.
  class Monitor
    Result = Data.define(:triggered, :signal_type, :window, :severity, :attributes,
                         :semantic_identity, :details) do
      def self.not_triggered(window:, details: {})
        new(triggered: false, signal_type: nil, window: window, severity: nil,
            attributes: {}, semantic_identity: nil, details: details)
      end

      def triggered? = triggered
    end

    MONITORS = {
      "blood_pressure_trajectory_change" => "Hypertension::TrajectoryChangeMonitor"
    }.freeze

    class << self
      def key = raise(NotImplementedError, "#{name} must define .key")
      def version = raise(NotImplementedError, "#{name} must define .version")
      def domain_key = raise(NotImplementedError, "#{name} must define .domain_key")

      # Default parameters ship with the DOMAIN PACK, never with platform core
      # (HO §31: "clinical threshold defaults should not be invented by
      # platform core"). Organization configuration overrides them.
      def default_parameters = {}

      def digest
        Definitions::DefinitionDigest.compute(
          key: key, version: version, parameters: default_parameters
        )
      end

      def find(monitor_key)
        name = MONITORS[monitor_key.to_s]
        raise ArgumentError, "no monitor registered for #{monitor_key.inspect}" if name.blank?

        name.constantize
      end

      def all = MONITORS.keys
    end

    def initialize(parameters: {})
      @parameters = self.class.default_parameters.merge(parameters.symbolize_keys)
    end

    attr_reader :parameters

    def evaluate(subject:, as_of:)
      raise NotImplementedError
    end
  end
end
