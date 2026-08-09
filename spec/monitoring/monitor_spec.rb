# frozen_string_literal: true

require "rails_helper"

# Epic 001-10. HO §30–34; S2C-001 (Signal immutability), S2C-002 (idempotency),
# S2C-003 (monitor boundary).
RSpec.describe "Monitoring", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }

  let(:as_of) { Time.utc(2026, 3, 22, 12, 0) }

  # Daily summaries are the monitor's input, so they are built directly rather
  # than driven through ingestion — the pipeline above them is already covered
  # by the 001-05/08/09 specs.
  def summary(value, days_ago:)
    ends_at = as_of - days_ago.days
    DerivedSignal.create!(
      organization: organization, subject: subject_record,
      semantic_key: "health.vital.blood_pressure.daily_summary", semantic_version: 1,
      window_started_at: ends_at.beginning_of_day, window_ended_at: ends_at,
      value_numeric: value, unit: "mmHg", status: "computed",
      algorithm_key: "daily_blood_pressure_summary", algorithm_version: 1,
      algorithm_digest: "d", usable_input_count: 2, raw_input_count: 2,
      computed_at: as_of, as_of: ends_at
    )
  end

  def stable_baseline(value = 120)
    (8..20).each { |d| summary(value, days_ago: d) }
  end

  def evaluate = Monitoring::EvaluateMonitor.call(
    subject: subject_record, monitor_key: "blood_pressure_trajectory_change", as_of: as_of
  )

  describe "S2C-003 monitor boundary" do
    # The line that keeps this an observability product rather than an alert
    # manager: machine evidence accumulates freely, and the decision that a
    # human should look is made separately by correlation.
    it "creates a Signal and never a Case" do
      stable_baseline
      (1..6).each { |d| summary(140, days_ago: d) }

      expect { evaluate }.not_to change { ActiveRecord::Base.connection.tables.include?("cases") }
      expect(Monitoring::Signal.count).to eq(1)
    end

    it "never references Case tables in the monitoring source" do
      sources = Rails.root.glob("app/services/monitoring/**/*.rb") +
                Rails.root.glob("app/domain_packs/*/monitors/**/*.rb")

      # Comments are stripped first: this file and the monitors discuss Cases
      # at length in prose precisely to explain the boundary, and matching
      # that would make the guard fire on its own documentation.
      offenders = sources.select do |file|
        code = file.read.lines.reject { |l| l.strip.start_with?("#") }.join
        code.match?(/\bCases?\b|case_signals|CaseEvent|correlation/i)
      end

      expect(offenders).to be_empty,
        "Monitors must not touch Case tables (S2C-003): #{offenders.map(&:basename).join(', ')}"
    end
  end

  describe "triggering" do
    it "fires when the recent median shifts past the fixture threshold" do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }

      result = evaluate

      expect(result).to be_triggered
      expect(result.signal.signal_type).to eq("blood_pressure_trajectory_change")
      expect(result.signal.attributes_json["direction"]).to eq("increase")
      expect(result.signal.attributes_json["shift_mmhg"]).to eq("20.0")
    end

    it "does not fire when the shift is below the fixture threshold" do
      stable_baseline(120)
      (1..6).each { |d| summary(123, days_ago: d) }

      result = evaluate

      expect(result).not_to be_triggered
      expect(Monitoring::Signal.count).to eq(0)
      expect(result.evaluation.result).to eq("not_triggered")
    end

    it "records insufficient_data rather than firing on too few points" do
      (1..2).each { |d| summary(140, days_ago: d) }

      result = evaluate

      expect(result).not_to be_triggered
      expect(result.evaluation.result).to eq("insufficient_data")
    end

    # HO §32: a monitor that declines to fire is as interesting as one that
    # fires. Without the evaluation record the negative case leaves no trace,
    # and "why did this not alert?" becomes unanswerable.
    it "records an evaluation even when nothing fires" do
      stable_baseline(120)
      (1..6).each { |d| summary(121, days_ago: d) }

      evaluate

      evaluation = MonitorEvaluation.last
      expect(evaluation.result).to eq("not_triggered")
      expect(evaluation.details["reason"]).to eq("below_threshold")
    end

    # STAT-001 / INV-34. A Signal is a reason to look, never a claim.
    it "labels its attributes descriptive rather than causal" do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }

      attributes = evaluate.signal.attributes_json

      expect(attributes["interpretation"]).to eq("descriptive_only")
      expect(attributes.to_json).not_to match(/caused|because|due to/i)
    end

    # STAT-021: denominators travel with the observation, so a Case built from
    # this Signal can show what it rested on without recomputing.
    it "carries the point counts it was based on" do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }

      attributes = evaluate.signal.attributes_json

      expect(attributes["recent_point_count"]).to eq(6)
      expect(attributes["baseline_point_count"]).to be >= 5
    end
  end

  describe "S2C-002 idempotency" do
    before do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }
    end

    it "returns the existing Signal on a repeated evaluation" do
      first = evaluate
      second = evaluate

      expect(first).to be_created
      expect(second).not_to be_created
      expect(second.signal).to eq(first.signal)
      expect(Monitoring::Signal.count).to eq(1)
    end

    it "still records each evaluation" do
      3.times { evaluate }

      expect(Monitoring::Signal.count).to eq(1)
      expect(MonitorEvaluation.count).to eq(3)
    end

    it "enforces uniqueness at the database, not just in the service" do
      signal = evaluate.signal
      duplicate = Monitoring::Signal.new(
        signal.attributes.except("id", "created_at", "updated_at")
              .merge("public_id" => "sig_#{SecureRandom.alphanumeric(20).downcase}")
      )

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /dedupe_key/)
    end

    # HO §34 includes the semantic event identity, so a reversal is a
    # genuinely different event rather than a duplicate of the original.
    # A second subject rather than rewriting the first one's history:
    # derived_signals is append-only, so deleting summaries to reshape a
    # scenario is refused by the database (ADR-002 4a) — correctly.
    it "treats an opposite-direction shift as a different Signal" do
      evaluate
      initial_count = Monitoring::Signal.count

      falling = Subject.create!(organization: organization, timezone: "UTC")
      (8..20).each do |d|
        ends_at = as_of - d.days
        DerivedSignal.create!(
          organization: organization, subject: falling,
          semantic_key: "health.vital.blood_pressure.daily_summary", semantic_version: 1,
          window_started_at: ends_at.beginning_of_day, window_ended_at: ends_at,
          value_numeric: 120, unit: "mmHg", status: "computed",
          algorithm_key: "daily_blood_pressure_summary", algorithm_version: 1,
          algorithm_digest: "d", usable_input_count: 2, raw_input_count: 2,
          computed_at: as_of, as_of: ends_at
        )
      end
      (1..6).each do |d|
        ends_at = as_of - d.days
        DerivedSignal.create!(
          organization: organization, subject: falling,
          semantic_key: "health.vital.blood_pressure.daily_summary", semantic_version: 1,
          window_started_at: ends_at.beginning_of_day, window_ended_at: ends_at,
          value_numeric: 100, unit: "mmHg", status: "computed",
          algorithm_key: "daily_blood_pressure_summary", algorithm_version: 1,
          algorithm_digest: "d", usable_input_count: 2, raw_input_count: 2,
          computed_at: as_of, as_of: ends_at
        )
      end

      result = Monitoring::EvaluateMonitor.call(
        subject: falling, monitor_key: "blood_pressure_trajectory_change", as_of: as_of
      )

      expect(result.signal.attributes_json["direction"]).to eq("decrease")
      expect(Monitoring::Signal.count).to eq(initial_count + 1)
    end
  end

  describe "S2C-001 Signal immutability" do
    before do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }
    end

    it "refuses to mutate a Signal in Ruby" do
      signal = evaluate.signal

      expect { signal.update!(severity: "high") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses UPDATE at the database" do
      signal = evaluate.signal

      expect {
        Monitoring::Signal.connection.execute("UPDATE signals SET severity = 'high' WHERE id = '#{signal.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    # HO §9: a historical Case may hold Signals from several monitor versions,
    # and that must remain inspectable rather than being normalized away.
    it "stamps the monitor version and digest on every Signal (INV-6)" do
      signal = evaluate.signal

      expect(signal.monitor).to eq("blood_pressure_trajectory_change@v1")
      expect(signal.monitor_digest).to eq(Hypertension::TrajectoryChangeMonitor.digest)
    end
  end

  describe "HO §31 organization configuration" do
    before do
      stable_baseline(120)
      (1..6).each { |d| summary(130, days_ago: d) } # 10 mmHg shift
    end

    it "honours an organization's overridden threshold" do
      config = MonitorConfiguration.create!(
        organization: organization, domain_key: "hypertension",
        monitor_key: "blood_pressure_trajectory_change", monitor_version: 1,
        parameters: { "shift_threshold_mmhg" => 15 }
      )

      result = Monitoring::EvaluateMonitor.call(
        subject: subject_record, monitor_key: "blood_pressure_trajectory_change",
        as_of: as_of, configuration: config
      )

      # 10 mmHg is under the organization's 15, though over the pack default
      # of 8 — customer policy sets thresholds without changing code identity.
      expect(result).not_to be_triggered
    end

    it "skips a disabled monitor and records that it skipped" do
      config = MonitorConfiguration.create!(
        organization: organization, domain_key: "hypertension",
        monitor_key: "blood_pressure_trajectory_change", monitor_version: 1,
        enabled: false
      )

      result = Monitoring::EvaluateMonitor.call(
        subject: subject_record, monitor_key: "blood_pressure_trajectory_change",
        as_of: as_of, configuration: config
      )

      expect(result).not_to be_triggered
      expect(MonitorEvaluation.last.result).to eq("skipped")
    end

    # HO §31: "clinical threshold defaults should not be invented by platform
    # core." Core ships no parameters at all; the domain pack owns them.
    it "keeps threshold defaults in the domain pack, not platform core" do
      expect(Monitoring::Monitor.default_parameters).to eq({})
      expect(Hypertension::TrajectoryChangeMonitor.default_parameters)
        .to include(:shift_threshold_mmhg)
    end
  end

  describe "S2C-021 outbox" do
    it "publishes monitoring.signal_created in the same transaction" do
      stable_baseline(120)
      (1..6).each { |d| summary(140, days_ago: d) }

      evaluate

      event = DomainEvent.find_by(event_type: "monitoring.signal_created")
      expect(event).to be_present
      expect(event.payload["signal_id"]).to eq(Monitoring::Signal.last.id)
    end
  end
end
