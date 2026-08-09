# frozen_string_literal: true

require "rails_helper"

# Epic 002-16, 002-18 to 002-20. HO §37, §43, §45, §46;
# S2C-011, S2C-012, S2C-013, S2C-014, S2C-015, S2C-016.
RSpec.describe "Case lifecycle", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:actor) { create_user(email: "clinician@example.test") }
  let!(:membership) { create_membership(organization: organization, user: actor, role: "clinician") }

  let(:detected_at) { Time.utc(2026, 3, 22, 12, 0) }

  def build_case(case_type: "blood_pressure_change", status: "new", **attrs)
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: case_type,
      title: "Blood pressure pattern change", status: status,
      started_at: detected_at - 7.days, detected_at: detected_at, **attrs
    )
  end

  def transition(case_record, to:, **opts)
    Cases::Transition.call(case_record: case_record, to: to, actor: actor, **opts)
  end

  describe "S2C-013 explicit transitions" do
    it "moves a Case through a legal transition and records the event" do
      case_record = build_case

      transition(case_record, to: "triaged")

      expect(case_record.reload.status).to eq("triaged")
      expect(case_record.case_events.pluck(:event_type)).to include("triaged")
    end

    # An impossible state must be unreachable by typo, not merely unhandled.
    it "refuses an illegal transition" do
      case_record = build_case(status: "new")

      expect { transition(case_record, to: "nonsense") }
        .to raise_error(Cases::Transition::InvalidTransition)
    end

    # S2C-016/017: reopening requires a new compatible Signal, so it belongs
    # to correlation. A manual resolved→investigating would reopen a Case with
    # no evidence behind it.
    it "refuses to reopen a resolved Case by transition" do
      case_record = build_case
      transition(case_record, to: "resolved", disposition: { code: "action_taken" })

      expect { transition(case_record, to: "investigating") }
        .to raise_error(Cases::Transition::InvalidTransition, /new compatible Signal/)
    end

    it "records every state change on the append-only timeline" do
      case_record = build_case

      transition(case_record, to: "triaged")
      transition(case_record, to: "investigating")

      expect(case_record.case_events.pluck(:event_type))
        .to eq(%w[triaged investigation_started])
      expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)
    end
  end

  describe "S2C-015 resolution requires a disposition" do
    # Refused rather than defaulted. A disposition the system invented would
    # corrupt the resolution feedback loop HO §43 depends on — every "action
    # taken" that nobody took makes monitor quality look better than it is.
    it "refuses to resolve without one" do
      case_record = build_case

      expect { transition(case_record, to: "resolved") }
        .to raise_error(Cases::Transition::DispositionRequired)
      expect(case_record.reload.status).to eq("new")
    end

    it "refuses to dismiss without one" do
      case_record = build_case

      expect { transition(case_record, to: "dismissed") }
        .to raise_error(Cases::Transition::DispositionRequired)
    end

    it "records the disposition and the event" do
      case_record = build_case

      transition(case_record, to: "resolved",
                 disposition: { code: "expected_change", notes: "Known medication change" })

      disposition = case_record.reload.latest_disposition
      expect(disposition.code).to eq("expected_change")
      expect(disposition.actor).to eq(actor)
      expect(case_record.case_events.pluck(:event_type)).to include("disposition_recorded", "resolved")
    end

    it "rejects a disposition code outside the taxonomy" do
      case_record = build_case

      expect {
        transition(case_record, to: "resolved", disposition: { code: "because_i_said_so" })
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # HO §43's feedback loop: a Case closed false_positive says something
    # about the monitor that produced it, which is what makes monitor quality
    # measurable at all (HO §129).
    it "distinguishes dispositions that indicate a monitor problem" do
      case_record = build_case
      transition(case_record, to: "dismissed", disposition: { code: "false_positive" })

      expect(case_record.reload.latest_disposition).to be_indicates_monitor_problem
    end

    # S2C-016: a reopened Case keeps its prior disposition visible. A column
    # on `cases` would have been overwritten.
    it "keeps earlier dispositions after a reopen" do
      case_record = build_case
      transition(case_record, to: "resolved", disposition: { code: "action_taken" })

      # Reopen the way correlation does.
      case_record.update!(status: "triaged", resolved_at: nil)
      transition(case_record, to: "resolved", disposition: { code: "expected_change" })

      expect(case_record.reload.dispositions.pluck(:code)).to eq(%w[action_taken expected_change])
    end
  end

  describe "S2C-014 watching" do
    # "Review occurred, but evidence does not justify closure or immediate
    # action" — a genuine third answer, and where STAT-036's "we do not know
    # yet" lives operationally.
    it "requires an explicit reevaluation condition" do
      case_record = build_case

      transition(case_record, to: "watching",
                 watch: { condition_type: "new_observation_count",
                          parameters: { "count" => 3 }, expires_at: detected_at + 14.days })

      condition = case_record.reload.watch_conditions.sole
      expect(condition.condition_type).to eq("new_observation_count")
      expect(condition.parameters["count"]).to eq(3)
      expect(case_record.watch_until).to be_present
    end

    it "is satisfied once the observation count is reached" do
      case_record = build_case
      transition(case_record, to: "watching",
                 watch: { condition_type: "new_observation_count", parameters: { "count" => 2 } })
      condition = case_record.reload.watch_conditions.sole

      expect(condition.satisfied_by?(case_record)).to be(false)

      source = Source.create!(organization: organization, key: "s", source_type: "synthetic",
                              display_name: "S")
      envelope = RawEnvelope.create!(
        organization: organization, source: source, source_record_id: "r",
        content_type: "application/json", object_key: "k", content_hash: "h",
        received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
      )
      2.times do |i|
        Observation.create!(
          organization: organization, subject: subject_record, source: source,
          raw_envelope: envelope, source_record_id: "r#{i}",
          semantic_key: "health.vital.blood_pressure.systolic", semantic_version: 1,
          value_numeric: 130, unit: "mmHg", observed_at: Time.current, normalized_at: Time.current,
          normalizer_key: "synthetic_bp_json", normalizer_version: 1
        )
      end

      expect(condition.satisfied_by?(case_record)).to be(true)
    end

    # A threshold inside a watch condition would duplicate a governed value
    # that already belongs to a monitor.
    it "leaves threshold evaluation to the monitor that owns the threshold" do
      case_record = build_case
      transition(case_record, to: "watching",
                 watch: { condition_type: "threshold_crossed", parameters: { "systolic" => 160 } })

      expect(case_record.reload.watch_conditions.sole.satisfied_by?(case_record)).to be(false)
    end
  end

  describe "S2C-011 priority is policy, not evidence" do
    # The rule that keeps this from becoming a risk score. A STRONG Difference
    # does not make a Case urgent and a WEAK one does not make it ignorable —
    # urgency is about how soon a human should look.
    it "does not read evidence_level" do
      source = Rails.root.join("app/domain_packs/hypertension/cases/priority_policy.rb").read
      code = source.lines.reject { |l| l.strip.start_with?("#") }.join

      expect(code).not_to match(/evidence_level|evidence_strength|STRONG|MODERATE/)
    end

    it "elevates a monitoring interruption, because evidence is being lost" do
      case_record = build_case(case_type: "monitoring_interruption")

      Cases::RecalculatePriority.call(case_record: case_record)

      expect(case_record.reload.review_priority).to eq("today")
      expect(case_record.priority_reasons.first["code"]).to eq("monitoring_interrupted")
    end

    it "elevates an aged Case that has never been reviewed" do
      case_record = build_case

      Cases::RecalculatePriority.call(case_record: case_record, as_of: detected_at + 20.days)

      expect(case_record.reload.review_priority).to eq("today")
      expect(case_record.priority_reasons.first["code"]).to eq("aged_unreviewed")
    end

    it "does not escalate an aged Case that has already been reviewed" do
      case_record = build_case
      transition(case_record, to: "triaged") # sets last_reviewed_at

      Cases::RecalculatePriority.call(case_record: case_record, as_of: detected_at + 20.days)

      expect(case_record.reload.review_priority).to eq("routine")
    end

    # STAT-036: "we do not know yet" is a successful output, and watching is
    # the right operational response — not escalation, and not closure.
    it "sets insufficient evidence to watch rather than escalating or closing" do
      case_record = build_case(analysis_status: "insufficient_evidence")

      # Well past the age threshold: a Case being watched for more data ages
      # by design, and escalating it for that would punish the honest answer.
      Cases::RecalculatePriority.call(case_record: case_record, as_of: detected_at + 60.days)

      expect(case_record.reload.review_priority).to eq("watch")
    end

    # S2C-012: no Case ever carries an unexplained ranking.
    it "records a reason for every priority, including the default" do
      case_record = build_case

      Cases::RecalculatePriority.call(case_record: case_record)

      reasons = case_record.reload.priority_reasons
      expect(reasons).to be_present
      expect(reasons.first).to include("code", "explanation", "source")
    end

    it "records a priority change on the timeline" do
      case_record = build_case(case_type: "monitoring_interruption")

      Cases::RecalculatePriority.call(case_record: case_record)

      event = case_record.case_events.find_by(event_type: "priority_changed")
      expect(event.payload["to"]).to eq("today")
    end

    # CLAUDE.md and HO §43 both forbid it explicitly.
    it "exposes no numeric score anywhere" do
      case_record = build_case
      Cases::RecalculatePriority.call(case_record: case_record)

      expect(case_record.reload.review_priority).to be_in(%w[now today routine watch])
      expect(case_record.priority_reasons.to_json).not_to match(/score|rank|\d+\s*points/i)
    end
  end
end
