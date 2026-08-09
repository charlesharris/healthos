# frozen_string_literal: true

module Cases
  # Applies the domain routing policy and records the decision (HO §44).
  #
  # Never overrides a human. If someone has already taken ownership or moved a
  # Case to a team, automatic routing leaves it alone — re-routing work an
  # operator has claimed is how a queue loses people's trust.
  class RouteCase
    def self.call(...) = new(...).call

    def initialize(case_record:, policy: Hypertension::RoutingPolicy, configuration: {})
      @case_record = case_record
      @policy = policy
      @configuration = configuration
    end

    def call
      return @case_record if @case_record.owner_id.present? || @case_record.team_id.present?

      result = @policy.call(case_record: @case_record, configuration: @configuration)
      return @case_record if result.team.nil?

      ActiveRecord::Base.transaction do
        @case_record.update!(team: result.team)
        CaseEvent.append!(
          case_record: @case_record, event_type: "assigned",
          payload: { "team_id" => result.team.id, "team" => result.team.name,
                     "reasons" => result.reasons, "assigned_by" => "routing_policy" }
        )
        # Deliberately NOT written to audit_events.
        #
        # HO §92 is a PROVIDER ACCESS audit — "who looked at what" — and every
        # entry names an accountable person, which is why actor_id is NOT
        # NULL. Automatic routing has no person, and relaxing the column to
        # admit one system row would weaken that guarantee for every other
        # row in the table.
        #
        # The assignment is not lost: the CaseEvent above records it with
        # `assigned_by: routing_policy`, which is where workflow history
        # belongs. Human reassignment, when the UI offers it in a later task,
        # does get an audit entry.
      end

      @case_record
    end
  end
end
