# frozen_string_literal: true

module Cases
  # Fires watch conditions that have come due (HO §45, S2C-014, epic 002-19).
  #
  # Quick Review could already park a Case with a stated condition for coming
  # back. This is the half that brings it back. Until it existed, "watching"
  # was indistinguishable from "quietly dropped" — which is the exact failure
  # mode the platform is built to surface in patient data, and it would have
  # been worse to have it in the tool itself.
  #
  # Two rules shape the whole class:
  #
  #   The machine reports; the human decides.  A satisfied condition returns a
  #   Case to `triaged` only if it is still `watching`. If a clinician already
  #   moved it on, the condition is closed out and the timeline records that
  #   it fired, but the state is left alone. Dragging a Case someone is
  #   actively investigating back to triaged would be the tool overruling the
  #   person using it (HO §120, "watch firing concurrent with manual triage").
  #
  #   Firing exactly once.  Jobs are retried and sweeps overlap, so evaluation
  #   is serialized on the Case row and re-reads the condition inside the lock.
  #   A watch that fires twice puts a duplicate on an append-only timeline,
  #   which cannot be taken back (S2C-010).
  class EvaluateWatchConditions
    def self.call(...) = new(...).call

    def initialize(case_record:, at: Time.current)
      @case_record = case_record
      @at = at
    end

    # Returns the conditions that fired, which is what the sweep counts.
    def call
      fired = []

      ActiveRecord::Base.transaction do
        # Serializes against a concurrent sweep and against a human
        # transitioning the same Case, so the status read below cannot go
        # stale between the check and the write.
        locked = CaseRecord.lock.find(@case_record.id)

        locked.watch_conditions.pending.order(:created_at).each do |condition|
          next unless condition.satisfied_by?(locked, at: @at)

          condition.update!(satisfied_at: @at)
          fired << condition
        end

        next if fired.empty?

        fired.each { |condition| append_satisfied_event(locked, condition) }
        return_to_queue(locked, fired.first) if locked.status == "watching"
      end

      # Priority is recalculated after commit, not inside: it appends its own
      # timeline event and reads observation counts, and neither needs to hold
      # the Case lock. A failure here leaves a correctly-triaged Case with a
      # stale priority, which the next sweep corrects — the opposite ordering
      # would leave the watch pending forever.
      RecalculatePriority.call(case_record: @case_record.reload) if fired.any?

      fired
    end

    private

    def append_satisfied_event(locked, condition)
      CaseEvent.append!(
        case_record: locked, event_type: "watch_satisfied", actor_type: "system",
        payload: {
          "watch_condition_id" => condition.id,
          "condition_type" => condition.condition_type,
          # Why it fired, in the operator's terms. "This came back because
          # three new readings arrived" is a different prompt to review than
          # "the timer ran out", and HO §84 says the queue owes the reader a
          # reason rather than a bare row.
          "reason" => reason_for(condition)
        },
        occurred_at: @at
      )
    end

    def reason_for(condition)
      case condition.condition_type
      when "time_elapsed" then "watch period elapsed"
      when "new_observation_count" then "#{condition.observations_since} new observations since the watch began"
      when "new_signal" then "a new Signal attached to this Case"
      else condition.condition_type
      end
    end

    # `triaged`, not `new`: this Case has been reviewed once, by a person who
    # decided to watch it. Sending it back to `new` would erase that.
    def return_to_queue(locked, condition)
      Transition.call(
        case_record: locked, to: "triaged", actor: nil, actor_type: "system",
        payload: { "trigger" => "watch_satisfied", "condition_type" => condition.condition_type }
      )
    end
  end
end
