# frozen_string_literal: true

module Outbox
  # Maps a durable event type to the Active Job that handles it (HO §49:
  # "Dispatcher converts durable domain events into Active Jobs").
  #
  # Registration is explicit rather than convention-derived, so that reading
  # this file tells you every consequence a given event can have. That
  # matters here more than in an ordinary app: HO §115 warns against hidden
  # workflow, and the outbox is precisely where invisible fan-out would hide.
  #
  # Handlers are named as strings and resolved at dispatch time so that a
  # handler living in a not-yet-written epic does not break boot.
  class Registry
    class UnregisteredEventType < StandardError; end

    # Populated as each epic adds its consumers. Empty in 001-03 by design:
    # the outbox skeleton lands before anything it will carry.
    #
    #   "monitoring.signal_created" => "Cases::CorrelateSignalJob"   (001-11)
    #   "cases.case_analysis_requested" => "Analysis::BuildCaseAnalysisJob" (003-22)
    DEFAULT_HANDLERS = {
      "ingestion.envelope_received" => "Normalization::NormalizeEnvelopeJob",
      "monitoring.signal_created" => "Cases::CorrelateSignalJob"
    }.freeze

    class << self
      def handlers
        @handlers ||= DEFAULT_HANDLERS.dup
      end

      def register(event_type, job_class_name)
        unless Outbox::EVENT_TYPES.include?(event_type)
          raise Outbox::UnknownEventType, "#{event_type.inspect} is not a registered event type"
        end

        handlers[event_type] = job_class_name.to_s
      end

      def job_for(event_type)
        name = handlers[event_type]
        raise UnregisteredEventType, "no handler registered for #{event_type.inspect}" if name.blank?

        name.constantize
      end

      def registered?(event_type) = handlers.key?(event_type)

      # Test seam. Production code never calls this.
      def reset!
        @handlers = DEFAULT_HANDLERS.dup
      end
    end
  end
end
