# frozen_string_literal: true

module Ops
  # The Ops Queue query (HO §85). "The queue is a Case list, not an alert
  # list" (HO §84) — the daily product surface.
  #
  # Extends Tenanted::Query, so organization is a required constructor
  # argument and never read from Current (HO §12, ADR-001's query-object seam).
  #
  # S2C-023: ordering is explainable SQL and policy, never an opaque score.
  # Every sort this object offers is a named, whitelisted list of columns with
  # a sentence describing it (#sort_explanation), which the queue renders. A
  # weighted numeric rank would be shorter to write and impossible for an
  # operator to argue with — HO §159 and STAT-024 forbid it.
  #
  # Note what is NOT here: evidence_level never appears in an ORDER BY.
  # Priority is operational policy and evidence strength is statistical
  # support (S2C-011); ordering work by evidence would collapse two
  # independent axes into the single importance score CLAUDE.md forbids.
  class CaseQuery < Tenanted::Query
    # Deliberately an ordered list rather than an integer column. A numeric
    # rank would invite arithmetic on it, and priority is a policy label, not
    # a magnitude (S2C-011).
    PRIORITY_ORDER = %w[now today routine watch].freeze

    # HO §85's default: review priority, then SLA/age, then detected_at.
    #
    # "Age" is time since anyone last looked, not time since the Case was
    # created — COALESCE(last_reviewed_at, detected_at). Sorting purely by
    # detected_at would keep pushing forward Cases somebody already handled
    # and parked, and bury work that has genuinely been ignored.
    SORTS = {
      "priority" => {
        label: "Priority, then age",
        explanation: "Review priority (now → today → routine → watch), " \
                     "then longest since anyone reviewed it, then oldest detection first.",
        columns: [ :priority_sql, "COALESCE(last_reviewed_at, detected_at) ASC", "detected_at ASC" ]
      },
      "age" => {
        label: "Age",
        explanation: "Longest since anyone reviewed it first, then review priority, " \
                     "then oldest detection first.",
        columns: [ "COALESCE(last_reviewed_at, detected_at) ASC", :priority_sql, "detected_at ASC" ]
      },
      "detected_at" => {
        label: "Newest first",
        explanation: "Most recently detected first, then review priority.",
        columns: [ "detected_at DESC", :priority_sql ]
      }
    }.freeze

    DEFAULT_SORT = "priority"
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    # Filter sentinel. `owner: nil` means "no owner filter"; `owner:
    # UNASSIGNED` means "show me the work nobody has claimed", which is a
    # different and operationally important question.
    UNASSIGNED = "unassigned"

    def initialize(organization:, membership: nil, status: nil, priority: nil,
                   owner: nil, team: nil, domain_key: nil, case_type: nil,
                   sort: nil, page: nil, per_page: nil, limit: nil)
      super(organization: organization, membership: membership)
      @status = Array(status).map(&:to_s).select(&:present?)
      @priority = Array(priority).map(&:to_s).select(&:present?)
      @owner = owner
      @team = team
      @domain_key = domain_key.presence
      @case_type = case_type.presence
      @sort = SORTS.key?(sort.to_s) ? sort.to_s : DEFAULT_SORT
      @per_page = clamp_per_page(limit || per_page)
      @page = [ page.to_i, 1 ].max
    end

    attr_reader :sort, :page, :per_page

    def resolve
      filtered
        .includes(:subject, :owner, :team)
        .order(Arel.sql(order_clause))
        .offset((page - 1) * per_page)
        .limit(per_page)
    end

    # Active work by default: resolved and dismissed Cases are history, not
    # queue.
    def self.default_statuses = Cases::CaseRecord::ACTIVE_STATUSES

    # Tab counts (HO §87). Counted with every filter EXCEPT status applied, so
    # switching tabs keeps the rest of the filter set and the numbers describe
    # what the operator would actually see.
    def counts_by_status
      base_relation(include_status: false).group(:status).count
    end

    def total_count = filtered.count

    def page_count = [ (total_count.to_f / per_page).ceil, 1 ].max

    def sort_explanation = SORTS.fetch(sort)[:explanation]

    # The ORDER BY as a human sentence plus the SQL itself. S2C-023 asks for
    # ordering a support engineer can explain to a customer; the SQL is the
    # proof and the sentence is the explanation.
    def order_sql = order_clause

    private

    def clamp_per_page(value)
      requested = value.to_i
      return DEFAULT_PER_PAGE if requested <= 0

      [ requested, MAX_PER_PAGE ].min
    end

    def filtered = base_relation(include_status: true)

    def base_relation(include_status:)
      relation = for_tenant(Cases::CaseRecord.all)

      relation = relation.where(status: @status) if include_status && @status.any?
      relation = relation.where(review_priority: @priority) if @priority.any?
      relation = apply_owner(relation)
      relation = apply_team(relation)
      relation = relation.where(domain_key: @domain_key) if @domain_key
      relation = relation.where(case_type: @case_type) if @case_type
      relation
    end

    # Accepts a record or a bare id. An id from another organization narrows
    # to nothing rather than being ignored, because the tenant predicate is
    # ANDed in either way — a filter that silently stops applying is worse
    # than one that returns nothing.
    def apply_owner(relation)
      return relation if @owner.nil?
      return relation.where(owner_id: nil) if @owner == UNASSIGNED

      relation.where(owner_id: identifier(@owner))
    end

    def apply_team(relation)
      return relation if @team.nil?
      return relation.where(team_id: nil) if @team == UNASSIGNED

      relation.where(team_id: identifier(@team))
    end

    def identifier(value) = value.respond_to?(:id) ? value.id : value

    # The trailing `id ASC` is not decoration. Ids are UUIDv7, so it is a
    # stable, unique tiebreak — without one, two Cases that tie on every sort
    # column can swap places between pages and offset pagination will show one
    # row twice and skip another.
    def order_clause
      columns = SORTS.fetch(sort)[:columns]
        .map { |column| column == :priority_sql ? priority_ordering : column }

      (columns + [ "id ASC" ]).join(", ")
    end

    # Explicit CASE expression rather than an enum column, so the ordering is
    # visible in the SQL a support engineer reads (S2C-023).
    def priority_ordering
      whens = PRIORITY_ORDER.each_with_index.map { |p, i| "WHEN #{ActiveRecord::Base.connection.quote(p)} THEN #{i}" }
      "CASE review_priority #{whens.join(' ')} ELSE #{PRIORITY_ORDER.size} END"
    end
  end
end
