# frozen_string_literal: true

module Monitoring
  # Runs one monitor for one subject and records the outcome.
  #
  # S2C-002: "monitor jobs may run repeatedly; the second execution should
  # return the existing Signal, not create a new one." Idempotency rests on
  # the unique index over (organization, deduplication_key), not on a
  # check-then-insert — concurrent evaluation is the case that breaks the
  # latter, which is exactly why S2C-022 puts it in the database.
  #
  # S2C-003: this service touches Signals and MonitorEvaluations only. It
  # never reads or writes Case tables.
  class EvaluateMonitor
    Result = Struct.new(:signal, :evaluation, :created, keyword_init: true) do
      def created? = created
      def triggered? = signal.present?
    end

    def self.call(...) = new(...).call

    def initialize(subject:, monitor_key:, as_of: Time.current, configuration: nil)
      @subject = subject
      @monitor_key = monitor_key
      @as_of = as_of
      @configuration = configuration
    end

    def call
      monitor_class = Monitoring::Monitor.find(@monitor_key)

      if configuration && !configuration.enabled?
        return Result.new(signal: nil, evaluation: record_evaluation(monitor_class, nil, "skipped",
                                                                     [ @as_of, @as_of ], {}), created: false)
      end

      monitor = monitor_class.new(parameters: configuration&.parameters || {})
      outcome = monitor.evaluate(subject: @subject, as_of: @as_of)

      unless outcome.triggered?
        result = outcome.details[:reason] == "insufficient_points" ? "insufficient_data" : "not_triggered"
        return Result.new(
          signal: nil,
          evaluation: record_evaluation(monitor_class, nil, result, outcome.window, outcome.details),
          created: false
        )
      end

      create_signal(monitor_class, outcome)
    end

    private

    attr_reader :subject, :as_of

    def configuration
      return @configuration if defined?(@configuration) && !@configuration.nil?

      @configuration = MonitorConfiguration.find_by(
        organization_id: subject.organization_id, monitor_key: @monitor_key
      )
    end

    def create_signal(monitor_class, outcome)
      dedupe = Monitoring::Signal.deduplication_key_for(
        organization: subject.organization, subject: subject,
        monitor_key: monitor_class.key, monitor_version: monitor_class.version,
        window: outcome.window, semantic_identity: outcome.semantic_identity
      )

      existing = Monitoring::Signal.find_by(organization_id: subject.organization_id, deduplication_key: dedupe)
      if existing
        return Result.new(
          signal: existing,
          evaluation: record_evaluation(monitor_class, existing, "triggered", outcome.window, outcome.details),
          created: false
        )
      end

      signal = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        signal = Monitoring::Signal.create!(
          organization: subject.organization, subject: subject,
          monitor_key: monitor_class.key, monitor_version: monitor_class.version,
          monitor_digest: monitor_class.digest,
          signal_type: outcome.signal_type, domain_key: monitor_class.domain_key,
          detected_at: as_of,
          window_started_at: outcome.window.first, window_ended_at: outcome.window.last,
          severity: outcome.severity, attributes_json: outcome.attributes,
          deduplication_key: dedupe
        )

        # S2C-021. The Signal and the intent to correlate it commit together,
        # so correlation can never be requested for a Signal that rolled back.
        Outbox.publish(
          organization: subject.organization, aggregate: signal,
          event_type: "monitoring.signal_created",
          payload: { "signal_id" => signal.id, "domain_key" => monitor_class.domain_key }
        )
      end

      Result.new(
        signal: signal,
        evaluation: record_evaluation(monitor_class, signal, "triggered", outcome.window, outcome.details),
        created: true
      )
    rescue ActiveRecord::RecordNotUnique
      found = Monitoring::Signal.find_by(organization_id: subject.organization_id, deduplication_key: dedupe)
      raise if found.nil?

      Result.new(
        signal: found,
        evaluation: record_evaluation(monitor_class, found, "triggered", outcome.window, outcome.details),
        created: false
      )
    end

    def record_evaluation(monitor_class, signal, result, window, details)
      MonitorEvaluation.create!(
        organization: subject.organization, subject: subject,
        monitor_key: monitor_class.key, monitor_version: monitor_class.version,
        window_started_at: window.first, window_ended_at: window.last,
        evaluated_at: as_of, result: result,
        details: details.deep_stringify_keys, signal: signal
      )
    end
  end
end
