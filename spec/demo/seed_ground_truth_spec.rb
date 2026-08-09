# frozen_string_literal: true

require "rails_helper"
require "rake"

# The demo seed states its ground truth in `lib/tasks/demo.rake`. This checks
# the system actually produces it.
#
# HO §127 and the epic 002 gate ask for a demo population; the do-not-ship
# list (HO §188) asks for no false positives. A demo whose claims are only
# printed, never verified, drifts the first time a threshold moves — and it
# drifts in the most damaging direction, because a demo is what someone is
# shown before they trust the system.
#
# Two failures this already caught, both in the seed rather than the platform:
# the source switch bled into the baseline window so no instrumentation Signal
# fired beside an apparent fall (STAT-035's exact failure), and the reopen
# readings landed on the current day, which day-aligned half-open windows
# deliberately exclude.
#
# DEMO_POPULATION=0 drops the background cohort: it exists to make the queue
# look like work, and it has no stated ground truth to check.
RSpec.describe "demo:seed ground truth", type: :model do
  # The seed runs once for the whole group — 150-odd ingest-and-normalize
  # round trips is too much to repeat per example. That puts it outside the
  # per-example transaction, so this group cleans up after itself explicitly,
  # as the migrator, because most of what the seed writes is append-only to
  # the application role.
  self.use_transactional_tests = false

  def self.silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  before(:all) do
    MigratorConnection.wipe_tenant_data!

    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:seed")

    ENV["DEMO_POPULATION"] = "0"
    Rake::Task["demo:seed"].reenable
    self.class.silence_stdout { Rake::Task["demo:seed"].invoke }
  end

  after(:all) do
    ENV.delete("DEMO_POPULATION")
    MigratorConnection.wipe_tenant_data!
  end

  let(:organization) { Organization.find_by!(slug: "demo-health") }

  def subject_for(mrn)
    SubjectIdentifier.find_by!(organization: organization, value: mrn).subject
  end

  def signal_types_for(mrn)
    Monitoring::Signal.where(subject: subject_for(mrn)).distinct.pluck(:signal_type).sort
  end

  def case_types_for(mrn)
    Cases::CaseRecord.where(subject: subject_for(mrn)).pluck(:case_type).sort
  end

  describe "the changes it injected are found" do
    it "raises a trajectory Case for the genuine rise (DEMO-001)" do
      expect(signal_types_for("DEMO-001")).to include("blood_pressure_trajectory_change")
      expect(case_types_for("DEMO-001")).to eq([ "blood_pressure_change" ])
    end

    it "raises a trajectory Case for the genuine fall (DEMO-004)" do
      expect(signal_types_for("DEMO-004")).to include("blood_pressure_trajectory_change")
    end
  end

  # HO §188: "no false positives on stable subjects" is on the do-not-ship
  # list, and it is the claim a demo is least able to make by looking
  # impressive.
  describe "it stays quiet where nothing happened" do
    %w[DEMO-002 DEMO-003].each do |mrn|
      it "raises nothing for the stable subject #{mrn}" do
        expect(signal_types_for(mrn)).to be_empty
        expect(case_types_for(mrn)).to be_empty
      end
    end

    # STAT-012's completeness gate. Two readings, both high — the values look
    # alarming and the denominator says nothing can be claimed from them.
    it "raises nothing for the too-sparse subject (DEMO-007)" do
      expect(signal_types_for("DEMO-007")).to be_empty
      expect(case_types_for("DEMO-007")).to be_empty
    end
  end

  # STAT-003 and STAT-035: measurement behaviour is first-class evidence, and
  # an instrumentation Finding takes precedence over a biological one.
  describe "measurement behaviour is surfaced, not mistaken for biology" do
    it "reports the interruption as a monitoring Case, not a BP Case (DEMO-005)" do
      expect(signal_types_for("DEMO-005")).to eq([ "measurement_frequency_change" ])
      expect(case_types_for("DEMO-005")).to eq([ "monitoring_interruption" ])
    end

    # The seed's most important subject. The values look like improvement; the
    # cuff changed. The instrumentation Signal must be attached to the SAME
    # Case as the apparent fall, because a clinician reading that Case needs
    # the possible explanation in front of them, not filed separately.
    it "puts the source change on the same Case as the apparent fall (DEMO-006)" do
      expect(signal_types_for("DEMO-006")).to include("source_change")

      case_record = Cases::CaseRecord.find_by!(subject: subject_for("DEMO-006"))
      attached = case_record.case_signals.includes(:signal).map { |cs| cs.signal.signal_type }

      expect(attached).to include("source_change", "blood_pressure_trajectory_change")
      expect(case_types_for("DEMO-006")).to eq([ "blood_pressure_change" ])
    end
  end

  # The epic 002 gate asks the demo to exercise the lifecycle, not only
  # detection.
  describe "the lifecycle states the gate asks for" do
    it "leaves one Case parked with a pending watch condition" do
      watching = Cases::CaseRecord.where(organization: organization, status: "watching")

      expect(watching.count).to eq(1)
      expect(watching.sole.watch_conditions.pending).to be_present
    end

    it "leaves one Case that was resolved and then reopened by a new Signal" do
      reopened = Cases::CaseRecord
        .where(organization: organization)
        .select { |c| c.case_events.exists?(event_type: "reopened") }

      expect(reopened.size).to eq(1)

      case_record = reopened.sole
      # S2C-016: reopening preserves history. The disposition from the first
      # resolution is still there, and the Case is active again.
      expect(case_record.status).to eq("triaged")
      expect(case_record.dispositions).to be_present
      expect(case_record.case_events.pluck(:event_type)).to include("resolved", "reopened")
      expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)
    end
  end
end
