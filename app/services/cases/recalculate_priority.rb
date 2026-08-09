# frozen_string_literal: true

module Cases
  # HO §43. Applies the domain's priority policy and records why.
  #
  # The policy is injected, so platform core carries no domain urgency rules
  # (S2C-025) — what counts as urgent in hypertension is not what counts as
  # urgent in post-op recovery.
  class RecalculatePriority
    def self.call(...) = new(...).call

    def initialize(case_record:, policy: Hypertension::PriorityPolicy, as_of: Time.current)
      @case_record = case_record
      @policy = policy
      @as_of = as_of
    end

    def call
      result = @policy.call(case_record: @case_record, as_of: @as_of)
      return @case_record if result.priority == @case_record.review_priority

      previous = @case_record.review_priority

      ActiveRecord::Base.transaction do
        @case_record.update!(review_priority: result.priority, priority_reasons: result.reasons)

        # S2C-012: a priority change is part of the workflow history, so an
        # operator can see not just what it is but when and why it moved.
        CaseEvent.append!(
          case_record: @case_record, event_type: "priority_changed",
          payload: { "from" => previous, "to" => result.priority, "reasons" => result.reasons }
        )
      end

      @case_record
    end
  end
end
