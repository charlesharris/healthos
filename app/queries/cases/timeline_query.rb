# frozen_string_literal: true

module Cases
  # The merged Case timeline (HO §90).
  #
  # Merges observations, signals, case events, dispositions and workflow
  # actions into one ordered sequence of typed entries. HO §90: "do not mutate
  # historical timeline records" — nothing here writes, and every source it
  # reads is append-only by grant.
  #
  # Typed entries rather than raw records, because the Workbench needs to
  # render heterogeneous things on one axis without knowing every model, and
  # because the timeline is the surface where "what happened, in what order"
  # has to be answerable at a glance (§89).
  class TimelineQuery < Tenanted::Query
    Entry = Struct.new(:at, :kind, :summary, :detail, :record_id, :record_type, keyword_init: true)

    def initialize(organization:, case_record:, membership: nil, window: nil)
      super(organization: organization, membership: membership)
      @case_record = case_record
      @window = window
    end

    def resolve
      entries = case_events + signals + observations + dispositions + workflow_actions

      # Stable ordering: ties broken by kind then id, so two things recorded in
      # the same instant do not swap places between renders. A timeline that
      # reorders itself is one a reader cannot trust.
      entries.sort_by { |e| [ e.at, e.kind, e.record_id.to_s ] }
    end

    private

    def in_window?(time)
      return true if @window.nil?

      time >= @window.first && time < @window.last
    end

    def case_events
      @case_record.case_events.filter_map do |event|
        next unless in_window?(event.occurred_at)

        Entry.new(at: event.occurred_at, kind: "case_event",
                  summary: event.event_type.humanize, detail: event.payload,
                  record_id: event.id, record_type: "Cases::CaseEvent")
      end
    end

    def signals
      @case_record.case_signals.includes(:signal).filter_map do |attachment|
        signal = attachment.signal
        next unless in_window?(signal.detected_at)

        Entry.new(at: signal.detected_at, kind: "signal",
                  summary: "#{signal.signal_type.humanize} (#{attachment.relationship})",
                  detail: signal.attributes_json.merge("monitor" => signal.monitor),
                  record_id: signal.id, record_type: "Monitoring::Signal")
      end
    end

    # Observations are included so a reader can see the readings a Signal was
    # drawn from on the same axis as the operational events. Bounded, because
    # a year of daily readings would bury the workflow entries the timeline
    # exists to show.
    def observations
      relation = Observation
        .where(organization_id: organization.id, subject_id: @case_record.subject_id)
        .order(observed_at: :desc)
        .limit(200)
      relation = relation.where(observed_at: @window.first...@window.last) if @window

      relation.map do |observation|
        Entry.new(
          at: observation.observed_at, kind: "observation",
          summary: observation.observed? ? "#{observation.semantic_key} #{observation.value_numeric}" : observation.quality_state,
          detail: { "quality_state" => observation.quality_state, "unit" => observation.unit },
          record_id: observation.id, record_type: "Observation"
        )
      end
    end

    def dispositions
      @case_record.dispositions.filter_map do |disposition|
        next unless in_window?(disposition.disposed_at)

        Entry.new(at: disposition.disposed_at, kind: "disposition",
                  summary: disposition.code.humanize, detail: { "notes" => disposition.notes },
                  record_id: disposition.id, record_type: "Cases::Disposition")
      end
    end

    def workflow_actions
      WorkflowAction.where(case_id: @case_record.id).filter_map do |action|
        next unless in_window?(action.created_at)

        Entry.new(at: action.created_at, kind: "workflow_action",
                  summary: "#{action.action_type.humanize} (#{action.status})",
                  detail: action.parameters,
                  record_id: action.id, record_type: "WorkflowAction")
      end
    end
  end
end
