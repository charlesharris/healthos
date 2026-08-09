# frozen_string_literal: true

require "rails_helper"

# Epic 002-19. HO §45, S2C-014.
#
# A watch that never fires is worse than no watch at all, because it looks
# like active monitoring. Quick Review could already start one; until now
# nothing brought the Case back.
RSpec.describe "S2C-014 watch evaluation", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:actor) { create_user(email: "clinician@example.test") }
  let!(:membership) { create_membership(organization: organization, user: actor, role: "clinician") }

  def build_watching_case(condition_type: "time_elapsed", expires_at: 1.hour.ago, parameters: {})
    case_record = Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      started_at: 10.days.ago, detected_at: 3.days.ago
    )

    Cases::Transition.call(
      case_record: case_record, to: "watching", actor: actor,
      watch: { condition_type: condition_type, parameters: parameters, expires_at: expires_at }
    )

    case_record.reload
  end

  describe "a satisfied condition returns the Case to the queue" do
    it "moves watching → triaged and marks the condition satisfied" do
      case_record = build_watching_case(expires_at: 1.hour.ago)

      Cases::EvaluateWatchConditions.call(case_record: case_record)

      expect(case_record.reload.status).to eq("triaged")
      expect(case_record.watch_conditions.sole.satisfied_at).to be_present
    end

    # The operator's question on reopening a watched Case is "why is this back
    # in front of me", and the timeline is where HO §39 says that lives.
    it "records why on the timeline" do
      case_record = build_watching_case(expires_at: 1.hour.ago)

      Cases::EvaluateWatchConditions.call(case_record: case_record)

      event = case_record.case_events.find_by(event_type: "watch_satisfied")
      expect(event).to be_present
      expect(event.actor_type).to eq("system")
      expect(event.payload["condition_type"]).to eq("time_elapsed")
      expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)
    end

    # HO §92 audits PROVIDER ACCESS — who looked at what. A machine firing a
    # timer is not a person reading a chart, and recording it as one would
    # dilute the trail a regulator reads. Same reasoning as Cases::RouteCase.
    it "writes no provider-access audit row for a system transition" do
      case_record = build_watching_case(expires_at: 1.hour.ago)

      expect { Cases::EvaluateWatchConditions.call(case_record: case_record) }
        .not_to change { AuditEvent.where(event_type: "case.state_changed").count }
    end
  end

  describe "an unsatisfied condition changes nothing" do
    it "leaves a Case whose watch has not expired alone" do
      case_record = build_watching_case(expires_at: 2.days.from_now)

      expect { Cases::EvaluateWatchConditions.call(case_record: case_record) }
        .not_to change { case_record.reload.status }

      expect(case_record.watch_conditions.sole.satisfied_at).to be_nil
    end

    it "leaves a new_observation_count watch alone below its count" do
      case_record = build_watching_case(
        condition_type: "new_observation_count", expires_at: nil, parameters: { "count" => 3 }
      )

      Cases::EvaluateWatchConditions.call(case_record: case_record)

      expect(case_record.reload.status).to eq("watching")
    end
  end

  # Jobs are retried and must never assume exactly-once delivery (CLAUDE.md).
  describe "retry safety" do
    it "is idempotent: a second evaluation fires nothing further" do
      case_record = build_watching_case(expires_at: 1.hour.ago)

      Cases::EvaluateWatchConditions.call(case_record: case_record)
      before = case_record.reload.case_events.count

      Cases::EvaluateWatchConditions.call(case_record: case_record)

      expect(case_record.reload.case_events.count).to eq(before)
      expect(case_record.status).to eq("triaged")
    end
  end

  # HO §120's "watch condition firing concurrent with manual triage".
  describe "§120 watch firing concurrent with manual triage" do
    # The human got there first. The condition is still satisfied and must be
    # closed out — leaving it pending would refire forever — but the machine
    # must not drag a Case a clinician is actively investigating back to
    # triaged. Transitions are the human's; the watch only reports.
    it "closes out the condition without overriding a human's newer state" do
      case_record = build_watching_case(expires_at: 1.hour.ago)
      Cases::Transition.call(case_record: case_record, to: "investigating", actor: actor)

      Cases::EvaluateWatchConditions.call(case_record: case_record.reload)

      expect(case_record.reload.status).to eq("investigating")
      expect(case_record.watch_conditions.sole.satisfied_at).to be_present
      expect(case_record.case_events.pluck(:event_type)).to include("watch_satisfied")
    end

    it "does not resurrect a Case a human resolved while the watch was pending" do
      case_record = build_watching_case(expires_at: 1.hour.ago)
      Cases::Transition.call(
        case_record: case_record, to: "resolved", actor: actor,
        disposition: { code: "action_taken" }
      )

      Cases::EvaluateWatchConditions.call(case_record: case_record.reload)

      expect(case_record.reload.status).to eq("resolved")
    end

    # Two workers picking up the same Case from an overlapping sweep must not
    # double-fire. Serialized on the Case row, like correlation is on the
    # scope row (S2C-006).
    it "fires exactly once under two concurrent evaluations" do
      case_record = build_watching_case(expires_at: 1.hour.ago)

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Cases::EvaluateWatchConditions.call(case_record: Cases::CaseRecord.find(case_record.id))
          end
        end
      end
      threads.each(&:join)

      expect(case_record.reload.case_events.where(event_type: "watch_satisfied").count).to eq(1)
      expect(case_record.status).to eq("triaged")
    end
  end

  describe "the periodic sweep" do
    it "only considers Cases with a pending condition" do
      due = build_watching_case(expires_at: 1.hour.ago)
      not_due = build_watching_case(expires_at: 2.days.from_now)

      Cases::WatchEvaluationJob.perform_now

      expect(due.reload.status).to eq("triaged")
      expect(not_due.reload.status).to eq("watching")
    end

    # An expired watch on a Case nobody closed is exactly the "monitoring
    # silently stopped" failure the platform exists to surface, so the sweep
    # must not skip organizations just because they are quiet.
    it "sweeps across organizations" do
      other_org = create_organization(name: "Southside", slug: "southside")
      other_subject = Subject.create!(organization: other_org, timezone: "UTC")
      other_case = Cases::CaseRecord.create!(
        organization: other_org, subject: other_subject,
        domain_key: "hypertension", case_type: "blood_pressure_change",
        title: "Blood pressure pattern change", status: "new",
        started_at: 10.days.ago, detected_at: 3.days.ago
      )
      Cases::Transition.call(
        case_record: other_case, to: "watching", actor: actor,
        watch: { condition_type: "time_elapsed", parameters: {}, expires_at: 1.hour.ago }
      )
      due = build_watching_case(expires_at: 1.hour.ago)

      Cases::WatchEvaluationJob.perform_now

      expect(due.reload.status).to eq("triaged")
      expect(other_case.reload.status).to eq("triaged")
    end
  end
end
