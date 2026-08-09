# frozen_string_literal: true

require "rails_helper"

# Epic 002-21. HO §84–86; S2C-011, S2C-019, S2C-023; INV-31.
RSpec.describe Ops::CaseQuery, type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_org) { create_organization(name: "Southside", slug: "southside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:other_subject) { Subject.create!(organization: other_org, timezone: "UTC") }
  let!(:user) { create_user(email: "clinician@example.test") }
  let!(:membership) { create_membership(organization: organization, user: user, role: "clinician") }
  let!(:team) { Team.create!(organization: organization, name: "clinical") }

  let(:now) { Time.utc(2026, 3, 22, 12, 0) }

  def build_case(organization: self.organization, subject: subject_record, **attrs)
    Cases::CaseRecord.create!(
      organization: organization, subject: subject,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      started_at: now - 7.days, detected_at: now, **attrs
    )
  end

  def query(**options)
    described_class.new(organization: organization, membership: membership, **options)
  end

  describe "S2C-023 explainable ordering" do
    it "orders by review priority, then age, then detection" do
      watch = build_case(review_priority: "watch", title: "watch")
      urgent = build_case(review_priority: "now", title: "now")
      routine = build_case(review_priority: "routine", title: "routine")
      today = build_case(review_priority: "today", title: "today")

      expect(query.resolve.to_a).to eq([ urgent, today, routine, watch ])
    end

    it "breaks a priority tie by longest since anyone reviewed it" do
      newest = build_case(title: "reviewed just now", last_reviewed_at: now)
      oldest = build_case(title: "never reviewed", detected_at: now - 30.days)

      expect(query.resolve.to_a).to eq([ oldest, newest ])
    end

    # The ordering has to be readable by a support engineer answering "why is
    # this at the top" — not inferred from a weight.
    it "exposes the ordering as SQL and as a sentence" do
      expect(query.order_sql).to include("CASE review_priority")
      expect(query.sort_explanation).to be_present
    end

    # S2C-011 and STAT-024. Evidence strength is statistical support; review
    # priority is operational policy. Ordering work by evidence would collapse
    # them into the single importance score CLAUDE.md forbids.
    it "never orders by evidence strength or any numeric score" do
      described_class::SORTS.each_key do |sort|
        sql = query(sort: sort).order_sql

        expect(sql).not_to include("evidence_level")
        expect(sql).not_to match(/score|weight|rank\(/i)
      end
    end

    it "ignores an unknown sort rather than interpolating it" do
      expect(query(sort: "'; DROP TABLE cases; --").sort).to eq(described_class::DEFAULT_SORT)
    end

    it "offers age and recency as alternative, still-explainable sorts" do
      old_high = build_case(review_priority: "now", title: "old urgent", detected_at: now - 30.days)
      new_low = build_case(review_priority: "watch", title: "new watch", detected_at: now)

      expect(query(sort: "detected_at").resolve.to_a).to eq([ new_low, old_high ])
      expect(query(sort: "age").resolve.to_a).to eq([ old_high, new_low ])
    end
  end

  describe "filters (HO §85)" do
    it "defaults to active work and excludes closed Cases" do
      active = build_case(title: "active")
      build_case(title: "closed", status: "resolved", resolved_at: now)

      result = query(status: described_class.default_statuses).resolve

      expect(result.to_a).to eq([ active ])
    end

    it "filters by status, priority, domain and case type" do
      target = build_case(status: "investigating", review_priority: "now", case_type: "care_gap")
      build_case(status: "new", review_priority: "routine")

      expect(query(status: "investigating").resolve.to_a).to eq([ target ])
      expect(query(priority: "now").resolve.to_a).to eq([ target ])
      expect(query(case_type: "care_gap").resolve.to_a).to eq([ target ])
      expect(query(domain_key: "oncology").resolve.to_a).to be_empty
    end

    it "filters by owner, by team, and by nobody at all" do
      mine = build_case(owner: user, title: "mine")
      teamed = build_case(team: team, title: "team")
      unclaimed = build_case(title: "unclaimed")

      expect(query(owner: user).resolve.to_a).to eq([ mine ])
      expect(query(team: team).resolve.to_a).to eq([ teamed ])
      expect(query(owner: described_class::UNASSIGNED).resolve.to_a).to contain_exactly(teamed, unclaimed)
      expect(query(team: described_class::UNASSIGNED).resolve.to_a).to contain_exactly(mine, unclaimed)
    end

    # A filter that silently stops applying is worse than one that returns
    # nothing: the operator would read someone else's queue as their own.
    it "narrows to nothing for an owner id from another organization" do
      build_case
      outsider = create_user(email: "outsider@example.test")
      create_membership(organization: other_org, user: outsider, role: "clinician")

      expect(query(owner: outsider.id).resolve.to_a).to be_empty
    end

    # S2C-019: analysis state never removes a Case from the queue, and the two
    # unhappy states are not the same state.
    it "keeps failed and insufficient_evidence Cases in the queue and distinct" do
      failed = build_case(analysis_status: "failed", title: "failed")
      insufficient = build_case(analysis_status: "insufficient_evidence", title: "insufficient")

      expect(query.resolve.to_a).to include(failed, insufficient)
      expect(failed.analysis_status).not_to eq(insufficient.analysis_status)
    end
  end

  describe "tab counts (HO §87)" do
    it "counts every status regardless of the status filter" do
      build_case(status: "new")
      build_case(status: "investigating")
      build_case(status: "resolved", resolved_at: now)

      counts = query(status: "new").counts_by_status

      expect(counts).to eq("new" => 1, "investigating" => 1, "resolved" => 1)
    end

    it "still honours the other filters, so the numbers match what you would see" do
      build_case(status: "new", owner: user)
      build_case(status: "investigating")

      expect(query(owner: user).counts_by_status).to eq("new" => 1)
    end
  end

  describe "pagination (HO §86)" do
    before { 5.times { |i| build_case(title: "case #{i}", detected_at: now - i.days) } }

    it "pages without losing the ordering" do
      first_page = query(per_page: 2, page: 1).resolve.to_a
      second_page = query(per_page: 2, page: 2).resolve.to_a

      expect(first_page.size).to eq(2)
      expect(second_page.size).to eq(2)
      expect(first_page & second_page).to be_empty
    end

    it "reports totals so the queue can say how much work there is" do
      paged = query(per_page: 2)

      expect(paged.total_count).to eq(5)
      expect(paged.page_count).to eq(3)
    end

    it "clamps an absurd page size rather than letting a URL scan the tenant" do
      expect(query(per_page: 100_000).per_page).to eq(described_class::MAX_PER_PAGE)
      expect(query(per_page: 0).per_page).to eq(described_class::DEFAULT_PER_PAGE)
      expect(query(page: -3).page).to eq(1)
    end
  end

  describe "INV-31 tenancy" do
    it "never returns another organization's Cases" do
      mine = build_case(title: "mine")
      build_case(organization: other_org, subject: other_subject, title: "theirs")

      expect(query.resolve.to_a).to eq([ mine ])
      expect(query.counts_by_status.values.sum).to eq(1)
    end

    it "requires an organization" do
      expect { described_class.new(organization: nil) }
        .to raise_error(Tenanted::Query::MissingOrganizationError)
    end

    it "refuses a membership from a different organization" do
      outsider = create_membership(organization: other_org, role: "clinician")

      expect { described_class.new(organization: organization, membership: outsider) }
        .to raise_error(Tenanted::Query::CrossTenantError)
    end
  end
end
