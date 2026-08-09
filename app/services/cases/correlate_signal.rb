# frozen_string_literal: true

module Cases
  # HO §40's correlation contract, in order:
  #
  #   1. check if already attached      6. apply domain correlation rules
  #   2. lock correlation scope         7. attach if exactly one compatible
  #   3. find active Cases              8. otherwise check reopen
  #   4. filter eligible statuses       9. otherwise create new Case
  #   5. check correlation windows
  #
  # Deterministic and rule-based (S2C-006). No LLM correlation, no embeddings,
  # no clustering — HO §40 forbids all three in v0.1, and a nondeterministic
  # correlation would make "why is this Signal on this Case" unanswerable.
  #
  # Everything after step 2 runs inside the scope row lock (HO §35), so
  # concurrent Signals for the same subject and domain serialize rather than
  # racing to create duplicate Cases (S2C-007).
  class CorrelateSignal
    Result = Struct.new(:case_record, :case_signal, :outcome, keyword_init: true) do
      def created? = outcome == :created
      def attached? = outcome == :attached
      def reopened? = outcome == :reopened
      def ambiguous? = outcome == :created_ambiguous
    end

    def self.call(...) = new(...).call

    def initialize(signal:, rules: Hypertension::CorrelationRules)
      @signal = signal
      @rules = rules
    end

    def call
      # Step 1, before taking the lock: an already-attached Signal is a
      # retried job (S2C-020), and there is nothing to serialize.
      existing = CaseSignal.find_by(signal_id: signal.id)
      if existing
        return Result.new(case_record: existing.case_record, case_signal: existing, outcome: :already_attached)
      end

      ActiveRecord::Base.transaction do
        # Step 2. Everything below is serial for this subject+domain.
        CorrelationScope.lock_for!(
          organization: signal.organization, subject: signal.subject, domain_key: signal.domain_key
        )

        # Re-read after acquiring the lock. A concurrent transaction may have
        # attached this Signal or created a Case while we waited — reading
        # before the lock would use a stale view and recreate the duplicate
        # the lock exists to prevent.
        again = CaseSignal.find_by(signal_id: signal.id)
        if again
          next Result.new(case_record: again.case_record, case_signal: again, outcome: :already_attached)
        end

        correlate
      end
    end

    private

    attr_reader :signal, :rules

    def correlate
      candidates = eligible_cases.select { |c| rules.compatible?(c, signal) }

      case candidates.size
      when 1 then attach(candidates.first, relationship: rules.relationship_for(candidates.first, signal))
      when 0 then reopen_or_create
      else ambiguous(candidates)
      end
    end

    # Steps 3–4.
    def eligible_cases
      CaseRecord
        .active
        .where(organization_id: signal.organization_id, subject_id: signal.subject_id,
               domain_key: signal.domain_key)
        .order(:detected_at)
        .to_a
    end

    # Step 8. S2C-016: reopening preserves history rather than starting a new
    # Case, but only inside the domain's horizon (S2C-017) — an old, unrelated
    # episode should become its own Case.
    def reopen_or_create
      case_type = rules.case_type_for(signal.signal_type)
      return create_case(case_type) if case_type.nil?

      horizon = rules.reopen_horizon_for(case_type)
      candidate = CaseRecord
        .where(organization_id: signal.organization_id, subject_id: signal.subject_id,
               domain_key: signal.domain_key, case_type: case_type, status: %w[resolved dismissed])
        .where(resolved_at: (signal.detected_at - horizon)..signal.detected_at)
        .order(resolved_at: :desc)
        .first

      return create_case(case_type) if candidate.nil?

      reopen(candidate)
    end

    def attach(case_record, relationship:, event_type: "signal_attached", extra: {})
      case_signal = CaseSignal.create!(
        organization_id: signal.organization_id, case_record: case_record, signal: signal,
        relationship: relationship, attached_at: Time.current,
        # HO §158 / S2C-012: the explanation is persisted, so support can say
        # why this attached without re-deriving it later.
        explanation: {
          "rule" => "domain_correlation",
          "signal_type" => signal.signal_type,
          "case_type" => case_record.case_type,
          "relationship" => relationship,
          "monitor" => signal.monitor
        }.merge(extra)
      )

      case_record.update!(last_signal_at: signal.detected_at)
      CaseEvent.append!(
        case_record: case_record, event_type: event_type,
        payload: { "signal_id" => signal.id, "relationship" => relationship }.merge(extra)
      )

      Result.new(case_record: case_record, case_signal: case_signal, outcome: :attached)
    end

    def reopen(case_record)
      # S2C-016: prior disposition and history remain. The status changes; the
      # timeline is never rewritten.
      case_record.update!(status: "triaged", resolved_at: nil, last_signal_at: signal.detected_at)
      CaseEvent.append!(
        case_record: case_record, event_type: "reopened",
        payload: { "signal_id" => signal.id, "reason" => "compatible_signal_within_reopen_horizon" }
      )

      result = attach(case_record, relationship: "reopening", event_type: "signal_attached")
      Result.new(case_record: case_record, case_signal: result.case_signal, outcome: :reopened)
    end

    # Step 9.
    def create_case(case_type, ambiguous_with: nil)
      case_type ||= rules.case_type_for(signal.signal_type)
      config = case_type ? rules.config_for(case_type) : nil

      case_record = CaseRecord.create!(
        organization_id: signal.organization_id, subject_id: signal.subject_id,
        domain_key: signal.domain_key, case_type: case_type || "unclassified",
        title: config&.dig(:title) || signal.signal_type.humanize,
        status: "new",
        # Priority policy lands in 002-16. Until then every Case is routine
        # with a stated reason, rather than silently ranked (S2C-011/012).
        review_priority: "routine",
        priority_reasons: [ { "code" => "default_pending_priority_policy", "source" => "001-11" } ],
        started_at: signal.window_started_at, detected_at: signal.detected_at,
        last_signal_at: signal.detected_at
      )

      CaseEvent.append!(
        case_record: case_record, event_type: "case_created",
        payload: { "signal_id" => signal.id, "case_type" => case_record.case_type }
      )

      if ambiguous_with
        # S2C-008 / HO §41: never silently merge. A new Case plus a recorded
        # ambiguity, so an operator can see the choice was made and why.
        CaseEvent.append!(
          case_record: case_record, event_type: "correlation_ambiguous",
          payload: {
            "signal_id" => signal.id,
            "candidate_case_ids" => ambiguous_with.map(&:id),
            "resolution" => "created_new_case",
            "reason" => "multiple_equally_plausible_cases"
          }
        )
      end

      case_signal = CaseSignal.create!(
        organization_id: signal.organization_id, case_record: case_record, signal: signal,
        relationship: "trigger", attached_at: Time.current,
        explanation: { "rule" => "new_case", "signal_type" => signal.signal_type }
      )

      publish_created(case_record)

      Result.new(
        case_record: case_record, case_signal: case_signal,
        outcome: ambiguous_with ? :created_ambiguous : :created
      )
    end

    def ambiguous(candidates)
      create_case(rules.case_type_for(signal.signal_type), ambiguous_with: candidates)
    end

    def publish_created(case_record)
      Outbox.publish(
        organization: signal.organization, aggregate: case_record,
        event_type: "cases.case_created",
        payload: { "case_id" => case_record.id, "signal_id" => signal.id }
      )
    end
  end
end
