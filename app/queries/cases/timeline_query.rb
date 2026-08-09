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

    # Rows read from `observations`, not entries emitted. One measurement event
    # of systolic + diastolic + pulse is three rows and one entry.
    OBSERVATION_ROW_LIMIT = 400

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

    # The reading cap is real and has to be visible. A timeline that silently
    # stops at 400 rows reads as "this is everything that happened", which is
    # the one thing a history must never imply.
    def truncated?
      observation_rows.length >= OBSERVATION_ROW_LIMIT
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
    #
    # Emitted as MEASUREMENT EVENTS rather than as rows. Systolic, diastolic
    # and pulse recorded together are one measurement, not three independent
    # observations (STAT-004/005) — and rendering them as three lines was not
    # merely verbose, it asserted a cadence the subject did not have. On the
    # demo Case it turned 21 measurements into 63 rows and buried all three
    # workflow entries underneath them.
    def observation_rows
      @observation_rows ||= begin
        relation = Observation
          .where(organization_id: organization.id, subject_id: @case_record.subject_id)
          .order(observed_at: :desc)
          .limit(OBSERVATION_ROW_LIMIT)
        relation = relation.where(observed_at: @window.first...@window.last) if @window

        relation.to_a
      end
    end

    def observations
      # Grouped by the recorded measurement event where there is one, and by
      # instant where there is not — a source that does not group its readings
      # still took them together.
      observation_rows
        .group_by { |row| row.observation_group_id || row.observed_at }
        .map { |_, rows| measurement_entry(rows) }
    end

    # The order a measurement's readings are listed in, asked of the domain
    # packs rather than decided here (INV-35). Sorting the keys alphabetically
    # printed "diastolic 70 · systolic 128", which is backwards from how every
    # clinician writes a blood pressure and reads as a transcription error.
    def key_order
      @key_order ||= Analysis::ContextDefinition.declared_key_order
    end

    def measurement_entry(rows)
      first = rows.min_by(&:observed_at)
      observed, absent = rows.partition(&:observed?)

      summary =
        if observed.any?
          observed
            .sort_by { |row| [ key_order.index(row.semantic_key) || key_order.length, row.semantic_key ] }
            .map { |row| "#{row.semantic_key.split('.').last.tr('_', ' ')} #{row.value_numeric.to_f.round(1)}" }
            .join(" · ")
        else
          # STAT-002/010: an absent measurement is a state from the taxonomy,
          # never a zero and never a blank.
          absent.map(&:quality_state).uniq.join(", ")
        end

      Entry.new(
        at: first.observed_at, kind: "observation", summary: summary,
        # Method stays because a change in it is the thing STAT-003 exists to
        # make visible. Reading count and units do not: the count is already
        # legible from the values listed in the summary, and the units came
        # out in whatever order the rows arrived, so consecutive identical
        # measurements rendered "bpm, mmHg" then "mmHg, bpm" and read as a
        # difference in the data.
        detail: { "method" => observed.filter_map(&:recording_method).uniq.sort.join(", ").presence,
                  "missing" => absent.map(&:quality_state).uniq.sort.join(", ").presence }.compact,
        record_id: first.observation_group_id || first.id,
        record_type: first.observation_group_id ? "ObservationGroup" : "Observation"
      )
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
