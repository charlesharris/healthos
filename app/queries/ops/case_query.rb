# frozen_string_literal: true

module Ops
  # The Ops Queue query (HO §85). "The queue is a Case list, not an alert
  # list" (HO §84) — the daily product surface.
  #
  # Extends Tenanted::Query, so organization is a required constructor
  # argument and never read from Current (HO §12, ADR-001's query-object seam).
  #
  # S2C-023: ordering is explainable SQL and policy, never an opaque score.
  # Sorted by review priority, then age — both inspectable, neither weighted
  # into a single number. HO §159 and STAT-024 forbid the alternative.
  class CaseQuery < Tenanted::Query
    # Deliberately an ordered list rather than an integer column. A numeric
    # rank would invite arithmetic on it, and priority is a policy label, not
    # a magnitude (S2C-011).
    PRIORITY_ORDER = %w[now today routine watch].freeze

    def initialize(organization:, membership: nil, status: nil, priority: nil,
                   owner: nil, team: nil, domain_key: nil, case_type: nil, limit: 100)
      super(organization: organization, membership: membership)
      @status = status
      @priority = priority
      @owner = owner
      @team = team
      @domain_key = domain_key
      @case_type = case_type
      @limit = limit
    end

    def resolve
      relation = for_tenant(Cases::CaseRecord.all)
        .includes(:subject, :owner, :team)

      relation = relation.where(status: Array(@status)) if @status.present?
      relation = relation.where(review_priority: Array(@priority)) if @priority.present?
      relation = relation.where(owner_id: @owner.id) if @owner
      relation = relation.where(team_id: @team.id) if @team
      relation = relation.where(domain_key: @domain_key) if @domain_key.present?
      relation = relation.where(case_type: @case_type) if @case_type.present?

      relation.order(Arel.sql(priority_ordering)).order(detected_at: :asc).limit(@limit)
    end

    # Active work by default: resolved and dismissed Cases are history, not
    # queue.
    def self.default_statuses = Cases::CaseRecord::ACTIVE_STATUSES

    def counts_by_status
      for_tenant(Cases::CaseRecord.all).group(:status).count
    end

    private

    # Explicit CASE expression rather than an enum column, so the ordering is
    # visible in the SQL a support engineer reads (S2C-023).
    def priority_ordering
      whens = PRIORITY_ORDER.each_with_index.map { |p, i| "WHEN #{ActiveRecord::Base.connection.quote(p)} THEN #{i}" }
      "CASE review_priority #{whens.join(' ')} ELSE #{PRIORITY_ORDER.size} END"
    end
  end
end
