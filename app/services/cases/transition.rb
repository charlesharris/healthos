# frozen_string_literal: true

module Cases
  # Explicit state transitions (HO §36, S2C-013).
  #
  # S2C-013: "controllers do not directly mutate arbitrary Case state." Every
  # state change goes through a transition object, which means every one
  # appends a CaseEvent and every one is a named, testable operation. A
  # controller calling `case.update!(status: ...)` would produce a Case whose
  # timeline does not explain how it got there — and the timeline is the
  # authoritative workflow history (HO §39).
  #
  # HO §37 warns against encoding every workflow nuance as a status. The seven
  # states are deliberately few; detail lives in CaseEvent, Disposition,
  # WorkflowAction and WatchCondition.
  class Transition
    class InvalidTransition < StandardError; end
    class DispositionRequired < StandardError; end

    # Which moves are legal. Absent pairs are not "unhandled" — they are
    # refused, so an impossible state cannot be reached by a typo.
    ALLOWED = {
      "new" => %w[triaged investigating watching waiting_external resolved dismissed],
      "triaged" => %w[investigating watching waiting_external resolved dismissed],
      "investigating" => %w[watching waiting_external resolved dismissed triaged],
      "watching" => %w[investigating triaged waiting_external resolved dismissed],
      "waiting_external" => %w[investigating watching triaged resolved dismissed],
      # Reopening is not a transition — it is CorrelateSignal's job, because
      # only a new compatible Signal justifies it (S2C-016/017). Allowing a
      # manual resolved→investigating here would let a Case be reopened with
      # no evidence behind it.
      "resolved" => [],
      "dismissed" => []
    }.freeze

    # S2C-015: closing work records what happened.
    CLOSING_STATES = %w[resolved dismissed].freeze

    def self.call(...) = new(...).call

    def initialize(case_record:, to:, actor:, disposition: nil, watch: nil, payload: {})
      @case_record = case_record
      @to = to.to_s
      @actor = actor
      @disposition = disposition
      @watch = watch
      @payload = payload
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        from = @case_record.status

        apply_state_change(from)
        record_disposition if closing?
        record_watch if @to == "watching" && @watch.present?

        CaseEvent.append!(
          case_record: @case_record,
          event_type: event_type_for(@to),
          actor_type: "user", actor_id: @actor&.id,
          payload: { "from" => from, "to" => @to }.merge(@payload)
        )

        publish_if_closing
      end

      @case_record
    end

    private

    def closing? = CLOSING_STATES.include?(@to)

    def validate!
      allowed = ALLOWED.fetch(@case_record.status) do
        raise InvalidTransition, "unknown current status #{@case_record.status.inspect}"
      end

      unless allowed.include?(@to)
        raise InvalidTransition,
          "cannot move a #{@case_record.status} Case to #{@to}" \
          "#{' — reopening requires a new compatible Signal (S2C-016)' if @case_record.resolved?}"
      end

      # S2C-015. Refused rather than defaulted: a disposition invented by the
      # system would corrupt the resolution feedback loop HO §43 depends on.
      return unless closing? && @disposition.blank?

      raise DispositionRequired, "resolving or dismissing a Case requires a disposition (S2C-015)"
    end

    def apply_state_change(_from)
      attributes = { status: @to, last_reviewed_at: Time.current }
      attributes[:resolved_at] = Time.current if closing?
      attributes[:watch_until] = @watch[:expires_at] if @to == "watching" && @watch.present?

      @case_record.update!(attributes)
    end

    def record_disposition
      Disposition.create!(
        organization_id: @case_record.organization_id, case_record: @case_record,
        actor: @actor, code: @disposition.fetch(:code),
        notes: @disposition[:notes], action_type: @disposition[:action_type],
        external_reference: @disposition[:external_reference],
        disposed_at: Time.current
      )

      CaseEvent.append!(
        case_record: @case_record, event_type: "disposition_recorded",
        actor_type: "user", actor_id: @actor&.id,
        payload: { "code" => @disposition.fetch(:code) }
      )
    end

    def record_watch
      WatchCondition.create!(
        organization_id: @case_record.organization_id, case_record: @case_record,
        created_by: @actor, condition_type: @watch.fetch(:condition_type),
        parameters: @watch.fetch(:parameters, {}), expires_at: @watch[:expires_at]
      )
    end

    def event_type_for(state)
      {
        "triaged" => "triaged",
        "investigating" => "investigation_started",
        "watching" => "watch_started",
        "waiting_external" => "external_action_created",
        "resolved" => "resolved",
        "dismissed" => "dismissed"
      }.fetch(state, "state_changed")
    end

    def publish_if_closing
      return unless closing?

      Outbox.publish(
        organization: @case_record.organization, aggregate: @case_record,
        event_type: "cases.case_resolved",
        payload: { "case_id" => @case_record.id, "status" => @to,
                   "disposition" => @disposition&.fetch(:code, nil) }
      )
    end
  end
end
