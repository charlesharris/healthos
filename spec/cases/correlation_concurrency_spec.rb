# frozen_string_literal: true

require "rails_helper"

# HO §120 — the must-pass concurrency test:
#
#   "three compatible Signals created nearly simultaneously, three correlation
#    jobs execute concurrently → one Case, three CaseSignal rows, complete
#    CaseEvent history"
#
# S2C-007: concurrent compatible Signals cannot create duplicate Cases.
#
# These use REAL THREADS against REAL CONNECTIONS. Transactional fixtures are
# off, because a test transaction would hide the very contention being tested:
# each thread needs its own connection and its own committed view, or the
# scope row lock is never actually contended and the spec proves nothing.
#
# The handover asks for this to run repeatedly in CI. LOOP_RUNS controls that
# without editing the file.
RSpec.describe "Correlation concurrency", type: :model do
  self.use_transactional_tests = false

  LOOP_RUNS = Integer(ENV.fetch("CORRELATION_LOOP_RUNS", 3))

  let(:base_time) { Time.utc(2026, 3, 22, 12, 0) }

  # Explicit cleanup, since nothing is rolled back for us. Order matters:
  # case_signals and case_events reference cases, and all three are append-only
  # to the app role — so teardown runs as the migrator.
  def cleanup!
    MigratorConnection.truncate!(
      %w[case_events case_signals cases case_correlation_scopes domain_events
         signals subject_identifiers subject_identities subjects organizations]
    )
  end

  before { cleanup! }
  after { cleanup! }

  def setup_scenario
    organization = Organization.create!(name: "Concurrency", slug: "conc-#{SecureRandom.hex(4)}")
    subject_record = Subject.create!(organization: organization, timezone: "UTC")

    signals = 3.times.map do |i|
      Monitoring::Signal.create!(
        organization: organization, subject: subject_record,
        monitor_key: "blood_pressure_trajectory_change", monitor_version: 1, monitor_digest: "d",
        signal_type: "blood_pressure_trajectory_change", domain_key: "hypertension",
        # Nearly simultaneous, and well inside the correlation window, so all
        # three are genuinely compatible with one another.
        detected_at: base_time + i.minutes,
        window_started_at: base_time - 7.days, window_ended_at: base_time,
        severity: "low", deduplication_key: Digest::SHA256.hexdigest("sig-#{i}-#{SecureRandom.hex(6)}")
      )
    end

    [ organization, subject_record, signals ]
  end

  LOOP_RUNS.times do |run|
    it "produces exactly one Case from three concurrent correlations (run #{run + 1}/#{LOOP_RUNS})" do
      _organization, subject_record, signals = setup_scenario

      # A barrier so all three threads reach the correlation at the same
      # moment. Without it they would serialize naturally and the lock would
      # never be contended — the spec would pass while testing nothing.
      barrier = Queue.new
      threads = signals.map do |signal|
        Thread.new do
          barrier.pop
          ActiveRecord::Base.connection_pool.with_connection do
            Cases::CorrelateSignal.call(signal: signal)
          end
        rescue StandardError => e
          e
        end
      end

      3.times { barrier << :go }
      results = threads.map(&:value)

      errors = results.select { |r| r.is_a?(StandardError) }
      expect(errors).to be_empty, "correlation raised: #{errors.map(&:message).join('; ')}"

      cases = Cases::CaseRecord.where(subject_id: subject_record.id)

      # The three assertions HO §120 names.
      expect(cases.count).to eq(1)
      expect(Cases::CaseSignal.where(case_id: cases.first.id).count).to eq(3)

      events = cases.first.case_events.order(:occurred_at, :id)
      expect(events.where(event_type: "case_created").count).to eq(1)
      expect(events.where(event_type: "signal_attached").count).to eq(2)

      # Every Signal accounted for, none silently dropped.
      expect(Cases::CaseSignal.where(case_id: cases.first.id).pluck(:signal_id))
        .to match_array(signals.map(&:id))
    end
  end

  it "keeps the CaseEvent hash chain intact under concurrent appends" do
    _organization, subject_record, signals = setup_scenario

    barrier = Queue.new
    threads = signals.map do |signal|
      Thread.new do
        barrier.pop
        ActiveRecord::Base.connection_pool.with_connection do
          Cases::CorrelateSignal.call(signal: signal)
        end
      rescue StandardError => e
        e
      end
    end
    3.times { barrier << :go }
    threads.each(&:join)

    case_record = Cases::CaseRecord.find_by(subject_id: subject_record.id)

    # The chain is computed inside the scope lock, so concurrent appends
    # cannot interleave and orphan a link (ADR-002 4c).
    expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)
  end

  it "does not serialize across different subjects" do
    organization = Organization.create!(name: "Parallel", slug: "par-#{SecureRandom.hex(4)}")

    subjects = 3.times.map { Subject.create!(organization: organization, timezone: "UTC") }
    signals = subjects.map do |subject_record|
      Monitoring::Signal.create!(
        organization: organization, subject: subject_record,
        monitor_key: "blood_pressure_trajectory_change", monitor_version: 1, monitor_digest: "d",
        signal_type: "blood_pressure_trajectory_change", domain_key: "hypertension",
        detected_at: base_time, window_started_at: base_time - 7.days, window_ended_at: base_time,
        severity: "low", deduplication_key: Digest::SHA256.hexdigest(SecureRandom.hex(8))
      )
    end

    threads = signals.map do |signal|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Cases::CorrelateSignal.call(signal: signal)
        end
      end
    end
    threads.each(&:join)

    # Three subjects, three scopes, three Cases. The lock is per
    # organization+subject+domain (HO §35), so unrelated subjects do not
    # queue behind each other — which matters at population scale.
    expect(Cases::CaseRecord.where(organization_id: organization.id).count).to eq(3)
  end

  it "does not duplicate when the same Signal is correlated concurrently" do
    _organization, subject_record, signals = setup_scenario
    signal = signals.first

    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Cases::CorrelateSignal.call(signal: signal)
        end
      rescue StandardError => e
        e
      end
    end
    results = threads.map(&:value)

    expect(results.grep(StandardError)).to be_empty
    # S2C-020: a retried job must not duplicate the attachment.
    expect(Cases::CaseSignal.where(signal_id: signal.id).count).to eq(1)
    expect(Cases::CaseRecord.where(subject_id: subject_record.id).count).to eq(1)
  end
end
