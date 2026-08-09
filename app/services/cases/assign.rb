# frozen_string_literal: true

module Cases
  # Human (re)assignment of a Case (HO §87 "assignment", §92 audit).
  #
  # The counterpart to RouteCase, which is automatic, assigns only a team, and
  # deliberately writes no audit row because no person is accountable for it.
  # This one always has a person: an operator claimed the work or handed it to
  # someone else, so it produces both a CaseEvent (workflow history) and an
  # AuditEvent (who did what).
  #
  # Exists as a service rather than a controller `update!` for the same reason
  # Transition does (S2C-013): a Case whose owner changed with nothing in its
  # timeline explaining how is a Case nobody can reconstruct. Assignment is
  # not a *state* change, so it does not belong in Transition's legality
  # table — mixing them would either bloat that table with pseudo-states or
  # tempt a caller to pass `to: current_status` just to move an owner.
  class Assign
    class NotAssignable < StandardError; end

    # Sentinel distinguishing "leave this alone" from "set this to nobody".
    # `owner: nil` unassigns; omitting owner leaves it untouched.
    UNCHANGED = :unchanged

    def self.call(...) = new(...).call

    def initialize(case_record:, actor:, owner: UNCHANGED, team: UNCHANGED)
      @case_record = case_record
      @actor = actor
      @owner = owner
      @team = team
    end

    def call
      validate!

      changes = pending_changes
      return @case_record if changes.empty?

      ActiveRecord::Base.transaction do
        @case_record.update!(changes)

        CaseEvent.append!(
          case_record: @case_record, event_type: "assigned",
          actor_type: "user", actor_id: @actor&.id,
          payload: {
            "owner_id" => @case_record.owner_id, "team_id" => @case_record.team_id,
            "team" => @case_record.team&.name, "assigned_by" => "user"
          }
        )

        Audit.record!(:case_assigned, case_record: @case_record, actor: @actor,
                      metadata: { "owner_id" => @case_record.owner_id,
                                  "team_id" => @case_record.team_id })
      end

      @case_record
    end

    private

    def pending_changes
      changes = {}
      changes[:owner_id] = @owner&.id if @owner != UNCHANGED && @owner&.id != @case_record.owner_id
      changes[:team_id] = @team&.id if @team != UNCHANGED && @team&.id != @case_record.team_id
      changes
    end

    def validate!
      # Closed work has no owner to accept it. Refused rather than allowed
      # quietly, because reassigning a resolved Case looks like reopening it
      # and is not (S2C-016: only a new compatible Signal reopens).
      if @case_record.resolved?
        raise NotAssignable, "a #{@case_record.status} Case cannot be reassigned"
      end

      validate_owner!
      validate_team!
    end

    def validate_owner!
      return if @owner == UNCHANGED || @owner.nil?

      return if @owner.membership_for(@case_record.organization)&.clinical_access?

      raise NotAssignable,
        "user #{@owner.id} has no active clinical membership in this organization"
    end

    def validate_team!
      return if @team == UNCHANGED || @team.nil?
      return if @team.organization_id == @case_record.organization_id

      raise NotAssignable, "team #{@team.id} belongs to another organization"
    end
  end
end
