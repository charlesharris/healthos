# frozen_string_literal: true

require "rails_helper"

# Epic 002-17 (routing), 002-23 (timeline), 002-24 (audit).
# HO §44, §90, §92, §157; S2C-006, S2C-025.
RSpec.describe "Routing, timeline and audit", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:actor) { create_user(email: "clinician@example.test") }
  let!(:membership) { create_membership(organization: organization, user: actor, role: "clinician") }
  let!(:clinical_team) { Team.create!(organization: organization, name: "clinical") }
  let!(:ops_team) { Team.create!(organization: organization, name: "operations") }

  let(:detected_at) { Time.utc(2026, 3, 22, 12, 0) }

  def build_case(case_type: "blood_pressure_change", **attrs)
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: case_type,
      title: "Blood pressure pattern change", status: "new",
      started_at: detected_at - 7.days, detected_at: detected_at, **attrs
    )
  end

  describe "HO §44 deterministic routing" do
    it "routes by case type" do
      Cases::RouteCase.call(case_record: (bp = build_case))
      Cases::RouteCase.call(case_record: (mi = build_case(case_type: "monitoring_interruption")))

      expect(bp.reload.team).to eq(clinical_team)
      expect(mi.reload.team).to eq(ops_team)
    end

    # S2C-006: the same Case must route the same way every time, and someone
    # must be able to say why. A routing decision nobody can reproduce is one
    # nobody can dispute.
    it "is deterministic across repeated evaluation" do
      results = 3.times.map do
        Hypertension::RoutingPolicy.call(case_record: build_case).team&.name
      end

      expect(results.uniq).to eq([ "clinical" ])
    end

    it "records why it routed where it did" do
      case_record = build_case
      Cases::RouteCase.call(case_record: case_record)

      event = case_record.case_events.find_by(event_type: "assigned")
      expect(event.payload["team"]).to eq("clinical")
      expect(event.payload["reasons"].first["code"]).to eq("default_case_type_rule")
    end

    it "honours a customer routing override" do
      case_record = build_case
      Cases::RouteCase.call(
        case_record: case_record,
        configuration: { "team_by_case_type" => { "blood_pressure_change" => "operations" } }
      )

      expect(case_record.reload.team).to eq(ops_team)
      expect(case_record.case_events.find_by(event_type: "assigned")
        .payload["reasons"].first["code"]).to eq("customer_routing_config")
    end

    # Re-routing work an operator has claimed is how a queue loses people's
    # trust.
    it "never overrides a human assignment" do
      case_record = build_case(owner: actor)

      Cases::RouteCase.call(case_record: case_record)

      expect(case_record.reload.team).to be_nil
      expect(case_record.owner).to eq(actor)
    end

    # Left unassigned and said so, rather than silently routed elsewhere. An
    # unroutable Case must stay visible.
    it "leaves a Case unassigned when the configured team does not exist" do
      case_record = build_case
      result = Hypertension::RoutingPolicy.call(
        case_record: case_record,
        configuration: { "team_by_case_type" => { "blood_pressure_change" => "nonexistent" } }
      )

      expect(result.team).to be_nil
      expect(result.reasons.first["code"]).to eq("team_missing")
    end

    # S2C-025: routing rules are domain-pack policy, not platform core.
    it "keeps domain vocabulary out of the core service" do
      code = Rails.root.join("app/services/cases/route_case.rb").read
        .lines.reject { |l| l.strip.start_with?("#") }.join

      expect(code).not_to match(/blood_pressure|hypertension|clinical|operations/)
    end
  end

  describe "HO §90 timeline" do
    let!(:source) do
      Source.create!(organization: organization, key: "s", source_type: "synthetic", display_name: "S")
    end
    let!(:envelope) do
      RawEnvelope.create!(
        organization: organization, source: source, source_record_id: "r",
        content_type: "application/json", object_key: "k", content_hash: "h",
        received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
      )
    end

    def timeline(case_record)
      Cases::TimelineQuery.new(
        organization: organization, case_record: case_record, membership: membership
      ).resolve
    end

    it "merges case events, signals, observations and dispositions on one axis" do
      case_record = build_case

      Observation.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, source_record_id: "r1",
        semantic_key: "health.vital.blood_pressure.systolic", semantic_version: 1,
        value_numeric: 142, unit: "mmHg", observed_at: detected_at - 1.day,
        normalized_at: Time.current, normalizer_key: "synthetic_bp_json", normalizer_version: 1
      )
      Cases::CaseEvent.append!(case_record: case_record, event_type: "case_created")
      Cases::Transition.call(case_record: case_record, to: "resolved", actor: actor,
                             disposition: { code: "action_taken" })

      kinds = timeline(case_record).map(&:kind).uniq

      expect(kinds).to include("case_event", "observation", "disposition")
    end

    # A timeline that reorders itself between renders is one a reader cannot
    # trust, so ties break deterministically.
    it "orders stably when entries share an instant" do
      case_record = build_case
      3.times { Cases::CaseEvent.append!(case_record: case_record, event_type: "case_created", occurred_at: detected_at) }

      first = timeline(case_record).map(&:record_id)
      second = timeline(case_record).map(&:record_id)

      expect(first).to eq(second)
    end

    it "is read-only over append-only sources (HO §90)" do
      case_record = build_case
      Cases::CaseEvent.append!(case_record: case_record, event_type: "case_created")

      expect { timeline(case_record) }.not_to change(Cases::CaseEvent, :count)
    end

    it "requires organization context like every tenanted query" do
      expect {
        Cases::TimelineQuery.new(organization: nil, case_record: build_case)
      }.to raise_error(Tenanted::Query::MissingOrganizationError)
    end
  end

  describe "HO §92 audit" do
    it "audits a state change with the actor who made it" do
      case_record = build_case

      expect {
        Cases::Transition.call(case_record: case_record, to: "triaged", actor: actor)
      }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:occurred_at).last
      expect(event.event_type).to eq("case.state_changed")
      expect(event.actor).to eq(actor)
      expect(event.metadata["to"]).to eq("triaged")
    end

    it "audits a disposition separately from the state change" do
      case_record = build_case

      Cases::Transition.call(case_record: case_record, to: "resolved", actor: actor,
                             disposition: { code: "action_taken" })

      types = AuditEvent.pluck(:event_type)
      expect(types).to include("case.state_changed", "case.disposition_entered")
    end

    # HO §92: ids, not values. The ids resolve, so there is no reason to
    # duplicate identity into the audit row.
    it "records ids rather than identifying values" do
      case_record = build_case
      SubjectIdentity.create!(subject: subject_record, first_name: "Zephyrine")

      Cases::Transition.call(case_record: case_record, to: "triaged", actor: actor)

      expect(AuditEvent.last.metadata.to_json).not_to include("Zephyrine")
      expect(AuditEvent.last.metadata["subject_id"]).to eq(subject_record.id)
    end

    # The distinction that matters: CaseEvent is product, AuditEvent is
    # compliance. A timeline full of "Dr X looked at this" would drown the
    # workflow history and leak who is reviewing whom to everyone with queue
    # access.
    it "keeps viewing out of the workflow timeline" do
      case_record = build_case
      events_before = case_record.case_events.count

      expect {
        Cases::Audit.record!(:case_viewed, case_record: case_record, actor: actor)
      }.to change(AuditEvent, :count).by(1)

      expect(case_record.case_events.count).to eq(events_before)
    end

    # Automatic routing has no accountable person, and audit_events.actor_id is
    # NOT NULL by design. The assignment is still recorded — as workflow
    # history, where it belongs.
    it "does not write an audit row for system routing" do
      case_record = build_case

      expect { Cases::RouteCase.call(case_record: case_record) }
        .not_to change(AuditEvent, :count)

      expect(case_record.case_events.find_by(event_type: "assigned")).to be_present
    end

    it "is append-only at the database" do
      case_record = build_case
      Cases::Transition.call(case_record: case_record, to: "triaged", actor: actor)
      event = AuditEvent.last

      expect {
        AuditEvent.connection.execute("DELETE FROM audit_events WHERE id = '#{event.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end
  end
end
