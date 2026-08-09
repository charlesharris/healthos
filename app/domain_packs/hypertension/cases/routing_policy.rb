# frozen_string_literal: true

module Hypertension
  # Deterministic routing (HO §44, S2C-006).
  #
  # Deterministic, and that word is doing real work: the same Case must route
  # the same way every time, and a support engineer must be able to say why it
  # landed where it did. HO §40 forbids LLM correlation for the same reason —
  # a routing decision nobody can reproduce is a routing decision nobody can
  # dispute.
  #
  # Routes to a TEAM, not a person. Assigning an owner automatically looks
  # helpful and is not: it creates the appearance of ownership without anyone
  # having accepted it, and work that is nominally owned is easier to overlook
  # than work that is visibly unassigned.
  module RoutingPolicy
    Result = Struct.new(:team, :owner, :reasons, keyword_init: true)

    # Team names a customer is expected to configure. Falling back to nil
    # rather than inventing a team means an unroutable Case shows up
    # unassigned in the queue instead of vanishing into a team that does not
    # exist.
    TEAM_BY_CASE_TYPE = {
      "monitoring_interruption" => "operations",
      "blood_pressure_change" => "clinical",
      "care_gap" => "operations"
    }.freeze

    module_function

    def call(case_record:, configuration: {})
      reasons = []
      overrides = configuration.fetch("team_by_case_type", {})

      name = overrides[case_record.case_type] || TEAM_BY_CASE_TYPE[case_record.case_type]

      if name.blank?
        reasons << reason("no_rule", "No routing rule for case type #{case_record.case_type}")
        return Result.new(team: nil, owner: nil, reasons: reasons)
      end

      team = Team.active.find_by(organization_id: case_record.organization_id, name: name)

      if team.nil?
        # The configured team does not exist in this organization. Left
        # unassigned and said so, rather than silently routing elsewhere.
        reasons << reason("team_missing", "Routing rule names team '#{name}', which does not exist")
        return Result.new(team: nil, owner: nil, reasons: reasons)
      end

      reasons << reason(
        overrides[case_record.case_type] ? "customer_routing_config" : "default_case_type_rule",
        "Case type #{case_record.case_type} routes to #{name}"
      )

      Result.new(team: team, owner: nil, reasons: reasons)
    end

    def reason(code, explanation)
      { "code" => code, "explanation" => explanation, "source" => "hypertension.routing_policy.v1" }
    end
  end
end
