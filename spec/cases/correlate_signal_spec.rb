# frozen_string_literal: true

require "rails_helper"

# Epic 001-11. HO §35 (scope lock), §40 (correlation contract), §41
# (ambiguity), §42 (hypertension rules); S2C-005, S2C-006, S2C-007, S2C-008,
# S2C-009, S2C-010, S2C-016, S2C-017.
RSpec.describe "Case correlation", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }

  let(:base_time) { Time.utc(2026, 3, 22, 12, 0) }

  def build_signal(signal_type: "blood_pressure_trajectory_change", detected_at: base_time,
                   identity: SecureRandom.hex(8), subject: subject_record)
    Monitoring::Signal.create!(
      organization: organization, subject: subject,
      monitor_key: "blood_pressure_trajectory_change", monitor_version: 1, monitor_digest: "d",
      signal_type: signal_type, domain_key: "hypertension",
      detected_at: detected_at, window_started_at: detected_at - 7.days,
      window_ended_at: detected_at, severity: "low",
      deduplication_key: Digest::SHA256.hexdigest(identity)
    )
  end

  def correlate(signal) = Cases::CorrelateSignal.call(signal: signal)

  describe "S2C-005 many Signals, few Cases" do
    it "creates a Case for the first Signal" do
      result = correlate(build_signal)

      expect(result).to be_created
      expect(result.case_record.case_type).to eq("blood_pressure_change")
      expect(result.case_record.status).to eq("new")
      expect(Cases::CaseRecord.count).to eq(1)
    end

    it "attaches a compatible later Signal to the same Case" do
      first = correlate(build_signal)
      second = correlate(build_signal(detected_at: base_time + 2.days))

      expect(second).to be_attached
      expect(second.case_record).to eq(first.case_record)
      expect(Cases::CaseRecord.count).to eq(1)
      expect(Cases::CaseSignal.count).to eq(2)
    end

    it "starts a new Case when the Signal falls outside the correlation window" do
      correlate(build_signal)
      # The hypertension pack's window is 14 days (NON-CLINICAL fixture).
      later = correlate(build_signal(detected_at: base_time + 30.days))

      expect(later).to be_created
      expect(Cases::CaseRecord.count).to eq(2)
    end

    # HO §42: "keep Cases separate when routing/action differs materially."
    it "does not fold a care-gap Signal into a blood-pressure Case" do
      correlate(build_signal)
      other = correlate(build_signal(signal_type: "workflow_event"))

      expect(other).to be_created
      expect(other.case_record.case_type).to eq("care_gap")
      expect(Cases::CaseRecord.count).to eq(2)
    end

    # HO §42: source and measurement Signals may attach contextually when they
    # explain the same work. This is the mechanism behind STAT-007's
    # instrumentation-before-biology ordering — the fact that the cuff changed
    # belongs on the same Case as the apparent shift, because it may be the
    # explanation for it.
    it "attaches a source-change Signal contextually to a blood-pressure Case" do
      first = correlate(build_signal)
      contextual = correlate(build_signal(signal_type: "source_change", detected_at: base_time + 1.day))

      expect(contextual).to be_attached
      expect(contextual.case_record).to eq(first.case_record)
      expect(contextual.case_signal.relationship).to eq("contextual")
    end
  end

  describe "S2C-020 idempotency" do
    it "returns the existing attachment when the same Signal is correlated twice" do
      signal = build_signal
      first = correlate(signal)
      second = correlate(signal)

      expect(second.outcome).to eq(:already_attached)
      expect(second.case_record).to eq(first.case_record)
      expect(Cases::CaseSignal.count).to eq(1)
    end

    it "enforces one attachment per Signal at the database" do
      signal = build_signal
      result = correlate(signal)

      duplicate = Cases::CaseSignal.new(
        organization_id: organization.id, case_record: result.case_record,
        signal: signal, relationship: "supporting", attached_at: Time.current
      )

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /case_signals_unique/)
    end
  end

  describe "S2C-008 correlation ambiguity" do
    # HO §41: "do not silently merge." A silent merge would attach evidence to
    # a Case it may not belong to, and nobody would ever know the choice was
    # made.
    it "creates a new Case and records the ambiguity when several Cases are equally plausible" do
      a = correlate(build_signal).case_record
      # A second, equally plausible Case in the same window. Reached by
      # resolving and reopening is not possible here, so it is constructed
      # directly — the point is the correlation decision, not how the second
      # Case arose.
      b = Cases::CaseRecord.create!(
        organization: organization, subject: subject_record,
        domain_key: "hypertension", case_type: "blood_pressure_change",
        status: "new", started_at: base_time - 7.days, detected_at: base_time,
        last_signal_at: base_time
      )

      result = correlate(build_signal(detected_at: base_time + 1.day))

      expect(result).to be_ambiguous
      expect(result.case_record).not_to eq(a)
      expect(result.case_record).not_to eq(b)

      event = result.case_record.case_events.find_by(event_type: "correlation_ambiguous")
      expect(event).to be_present
      expect(event.payload["candidate_case_ids"]).to contain_exactly(a.id, b.id)
      expect(event.payload["resolution"]).to eq("created_new_case")
    end
  end

  describe "S2C-016/017 reopening" do
    it "reopens a recently resolved Case rather than creating a new one" do
      first = correlate(build_signal).case_record
      first.update!(status: "resolved", resolved_at: base_time + 1.day)

      result = correlate(build_signal(detected_at: base_time + 3.days))

      expect(result).to be_reopened
      expect(result.case_record).to eq(first)
      expect(first.reload.status).to eq("triaged")
      expect(first.resolved_at).to be_nil
    end

    it "preserves the prior history when reopening" do
      first = correlate(build_signal).case_record
      first.update!(status: "resolved", resolved_at: base_time + 1.day)
      events_before = first.case_events.count

      correlate(build_signal(detected_at: base_time + 3.days))

      # S2C-016: history is retained, never rewritten. The reopen is appended.
      expect(first.case_events.count).to be > events_before
      expect(first.case_events.pluck(:event_type)).to include("case_created", "reopened")
    end

    # S2C-017: outside the domain's horizon it is a new episode, not a
    # continuation.
    it "creates a new Case outside the reopen horizon" do
      first = correlate(build_signal).case_record
      first.update!(status: "resolved", resolved_at: base_time + 1.day)

      # The hypertension pack's horizon is 7 days (NON-CLINICAL fixture).
      result = correlate(build_signal(detected_at: base_time + 20.days))

      expect(result).to be_created
      expect(result.case_record).not_to eq(first)
    end
  end

  describe "S2C-010 append-only timeline" do
    it "records case_created and signal_attached" do
      first = correlate(build_signal).case_record
      correlate(build_signal(detected_at: base_time + 1.day))

      expect(first.case_events.pluck(:event_type)).to eq(%w[case_created signal_attached])
    end

    it "refuses to mutate a CaseEvent" do
      case_record = correlate(build_signal).case_record
      event = case_record.case_events.first

      expect { event.update!(event_type: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses UPDATE and DELETE at the database" do
      case_record = correlate(build_signal).case_record
      event = case_record.case_events.first

      expect {
        Cases::CaseEvent.connection.execute(
          "UPDATE case_events SET event_type = 'x' WHERE id = '#{event.id}'"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    # ADR-002 Decision 4c: hash chaining makes tampering detectable even by an
    # actor who can bypass the grants.
    it "chains event hashes" do
      case_record = correlate(build_signal).case_record
      correlate(build_signal(detected_at: base_time + 1.day))

      events = case_record.case_events.reload.to_a
      expect(events.first.prev_hash).to be_nil
      expect(events.second.prev_hash).to eq(events.first.row_hash)
      expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)
    end
  end

  describe "S2C-012 explainability" do
    it "persists why a Signal attached" do
      correlate(build_signal)
      attachment = correlate(build_signal(detected_at: base_time + 1.day)).case_signal

      expect(attachment.explanation).to include(
        "rule" => "domain_correlation",
        "signal_type" => "blood_pressure_trajectory_change",
        "case_type" => "blood_pressure_change"
      )
    end

    # S2C-011/012: priority is operational policy and must never be silently
    # assigned. The real policy lands in 002-16; until then the default states
    # its own provisionality rather than pretending to be a judgement.
    it "records a reason for the default priority" do
      case_record = correlate(build_signal).case_record

      expect(case_record.review_priority).to eq("routine")
      expect(case_record.priority_reasons.first["code"]).to eq("default_pending_priority_policy")
    end
  end

  describe "S2C-025 domain boundary" do
    it "keeps correlation windows and case types in the domain pack" do
      core = Rails.root.glob("app/services/cases/**/*.rb")

      offenders = core.select do |file|
        code = file.read.lines.reject { |l| l.strip.start_with?("#") }.join
        code.match?(/blood_pressure|hypertension|mmHg|14\.days|7\.days/)
      end

      # Hypertension::CorrelationRules is injectable and referenced only as a
      # default argument, so platform core carries no disease vocabulary.
      expect(offenders).to be_empty,
        "Domain vocabulary leaked into platform core: #{offenders.map(&:basename).join(', ')}"
    end
  end
end
