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

    # actor_type "system" is for transitions no person asked for — a watch
    # condition firing, for example. It is not merely a null actor: it changes
    # what gets audited (see below), so it has to be stated rather than
    # inferred from `actor.nil?`, which is also true of a deleted user.
    ACTOR_TYPES = %w[user system].freeze

    def initialize(case_record:, to:, actor:, actor_type: "user", disposition: nil, watch: nil,
                   payload: {})
      raise ArgumentError, "unknown actor_type #{actor_type.inspect}" unless
        ACTOR_TYPES.include?(actor_type.to_s)

      @case_record = case_record
      @to = to.to_s
      @actor = actor
      @actor_type = actor_type.to_s
      @disposition = disposition
      @watch = watch
      @payload = payload
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        serialize_against_correlation! if closing?

        from = @case_record.status

        apply_state_change(from)
        record_disposition if closing?
        record_watch if @to == "watching" && @watch.present?

        CaseEvent.append!(
          case_record: @case_record,
          event_type: event_type_for(@to),
          actor_type: @actor_type, actor_id: @actor&.id,
          payload: { "from" => from, "to" => @to }.merge(@payload)
        )

        record_access_audit(from)

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

    # HO §120: "Case resolution concurrent with Signal arrival".
    #
    # Closing is the one transition that changes what correlation sees. A
    # Signal arriving at an active Case attaches to it; the same Signal
    # arriving a moment later, at a resolved Case, reopens it (S2C-016). Those
    # are different, both correct, and the difference turns on a status read
    # that correlation performs inside the scope lock.
    #
    # Without taking the same lock, a close can commit in the middle of a
    # correlation that has already read this Case as active. What happened
    # before this line existed: the correlation's write lost the optimistic
    # lock race, raised StaleObjectError, and the Signal was dropped until a
    # job retry picked it up — an error where there should have been a
    # reopen.
    #
    # Closing only. new→triaged and watching→investigating do not change
    # eligibility (both are active), so locking them would serialize routine
    # queue work behind correlation for no benefit. The lock is per
    # organization+subject+domain, so unrelated subjects still close in
    # parallel.
    def serialize_against_correlation!
      CorrelationScope.lock_for!(
        organization: @case_record.organization,
        subject: @case_record.subject,
        domain_key: @case_record.domain_key
      )

      # Re-read behind the lock. A correlation that just committed may have
      # reopened this Case, in which case the status we validated against is
      # stale and the close has to be re-judged against what is actually true.
      @case_record.reload
      validate!
    end

    def apply_state_change(_from)
      attributes = { status: @to, last_reviewed_at: Time.current }
      attributes[:resolved_at] = Time.current if closing?
      attributes[:watch_until] = @watch[:expires_at] if @to == "watching" && @watch.present?

      @case_record.update!(attributes)
    end

    # Audited here rather than in the controller: S2C-013 already routes every
    # state change through this object, so auditing here means a caller cannot
    # forget. HO §157 requires the trail to be complete, not conventional.
    #
    # System transitions are deliberately excluded. HO §92's audit answers
    # "who looked at what" about PEOPLE; a timer firing is not a provider
    # accessing health data, and logging it as one would dilute the trail
    # someone has to read during an access review. The event is still on the
    # CaseEvent timeline, which is where machine activity belongs. Same
    # reasoning as Cases::RouteCase.
    def record_access_audit(from)
      return unless @actor_type == "user"

      Audit.record!(:case_state_changed, case_record: @case_record, actor: @actor,
                    metadata: { "from" => from, "to" => @to })
      return unless closing?

      Audit.record!(:disposition_entered, case_record: @case_record, actor: @actor,
                    metadata: { "code" => @disposition.fetch(:code) })
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
        actor_type: @actor_type, actor_id: @actor&.id,
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
