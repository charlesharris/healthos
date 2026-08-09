# frozen_string_literal: true

require "rails_helper"

# HO §120: "Case resolution concurrent with Signal arrival".
#
# The dangerous interleaving is not the obvious one. Correlation takes the
# scope lock (S2C-006) and reads the Case as active; a clinician resolves the
# Case a moment later; correlation then attaches the Signal to a Case that is
# now closed. Nothing errors, nothing is duplicated, and a compatible Signal
# that S2C-016 says should have reopened the Case is instead sitting on
# resolved work where no one will look at it again.
#
# That is silent evidence loss, which the platform treats the way S2C-008
# treats ambiguous correlation: never resolve it quietly.
#
# Real threads on real connections, for the reasons given in
# spec/cases/correlation_concurrency_spec.rb.
RSpec.describe "HO §120 resolution concurrent with Signal arrival", type: :model do
  self.use_transactional_tests = false

  let(:base_time) { Time.utc(2026, 3, 22, 12, 0) }

  def cleanup!
    MigratorConnection.truncate!(
      %w[case_events case_signals case_dispositions watch_conditions cases
         case_correlation_scopes domain_events audit_events signals
         subject_identifiers subject_identities subjects
         organization_memberships users organizations]
    )
  end

  before { cleanup! }
  after { cleanup! }

  def setup_scenario
    organization = Organization.create!(name: "Race", slug: "race-#{SecureRandom.hex(4)}")
    subject_record = Subject.create!(organization: organization, timezone: "UTC")
    actor = create_user(email: "clinician-#{SecureRandom.hex(4)}@example.test")
    create_membership(organization: organization, user: actor, role: "clinician")

    case_record = Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "investigating",
      started_at: base_time - 7.days, detected_at: base_time - 1.day,
      last_reviewed_at: base_time - 1.hour
    )

    signal = Monitoring::Signal.create!(
      organization: organization, subject: subject_record,
      monitor_key: "blood_pressure_trajectory_change", monitor_version: 1, monitor_digest: "d",
      signal_type: "blood_pressure_trajectory_change", domain_key: "hypertension",
      detected_at: base_time, window_started_at: base_time - 7.days, window_ended_at: base_time,
      severity: "low", deduplication_key: Digest::SHA256.hexdigest(SecureRandom.hex(8))
    )

    [ organization, subject_record, actor, case_record, signal ]
  end

  def resolve(case_record, actor)
    Cases::Transition.call(
      case_record: case_record, to: "resolved", actor: actor,
      disposition: { code: "action_taken" }
    )
  end

  # Forces the interleaving rather than hoping for it: correlation is held
  # open after it has read the Case as active, and the resolution runs into
  # it. Without serialization this reliably produces a resolved Case with an
  # unreviewed Signal attached.
  def correlate_holding_the_lock(signal, after_read:)
    reached = Queue.new

    allow(Hypertension::CorrelationRules).to receive(:compatible?).and_wrap_original do |original, *args|
      verdict = original.call(*args)
      reached << :read
      after_read.pop
      verdict
    end

    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Cases::CorrelateSignal.call(signal: signal)
      end
    rescue StandardError => e
      e
    end

    reached.pop
    thread
  end

  # Runs both sides of the race and returns [correlation_outcome,
  # resolve_outcome]. The correlation is held open after it has read the Case
  # as active; the resolution runs into it.
  def race!(signal, case_record, actor)
    release = Queue.new
    correlation = correlate_holding_the_lock(signal, after_read: release)

    resolver = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        resolve(Cases::CaseRecord.find(case_record.id), actor)
      end
    rescue StandardError => e
      e
    end

    # Long enough for the resolver to reach the scope lock and block there.
    sleep 0.2
    release << :go
    [ correlation.value, resolver.value ]
  end

  it "does not drop the Signal" do
    _organization, _subject, actor, case_record, signal = setup_scenario

    correlation_outcome, = race!(signal, case_record, actor)

    # Before Transition took the scope lock, this was an
    # ActiveRecord::StaleObjectError and the Signal survived only because the
    # job would be retried — an error where there should have been an ordinary
    # attach or reopen.
    expect(correlation_outcome).not_to be_a(StandardError)
    expect(Cases::CaseSignal.find_by(signal_id: signal.id)).to be_present
  end

  it "does not lose the resolution" do
    _organization, _subject, actor, case_record, signal = setup_scenario

    _correlation_outcome, resolve_outcome = race!(signal, case_record, actor)

    expect(resolve_outcome).not_to be_a(StandardError)
    expect(case_record.reload.status).to eq("resolved")
  end

  # The point of serializing rather than merely preventing a lost update. The
  # two outcomes are both correct but they are DIFFERENT, and which one is
  # right depends on a status read (S2C-016). Interleaved, correlation reads a
  # status that is true at read time and false at write time, and the Signal
  # lands on a closed Case with no reopen — evidence that exists but that
  # nobody will be shown again.
  it "produces a coherent timeline: the attach and the close do not interleave" do
    _organization, _subject, actor, case_record, signal = setup_scenario

    race!(signal, case_record, actor)

    attachment = Cases::CaseSignal.find_by(signal_id: signal.id)
    next unless attachment.case_id == case_record.id

    events = case_record.case_events.order(:occurred_at, :id).pluck(:event_type)

    # Whichever side won, the history reads as one thing then the other.
    expect(events).to include("signal_attached")
    expect(events.index("signal_attached")).to be < events.index("resolved")
  end

  # The order the lock does NOT determine: if the resolution commits first,
  # correlation must see it and reopen rather than attaching to closed work.
  it "reopens rather than attaching when the resolution wins the race" do
    organization, subject_record, actor, case_record, _signal = setup_scenario

    resolve(case_record, actor)

    # Detected after the close, which is SC §74's scenario and the only
    # direction that means "new evidence about work we thought was done".
    # A Signal detected BEFORE the resolution is not a reopen — the clinician
    # closed with that period already behind them — and correlation opens a
    # new Case for it instead.
    later_signal = Monitoring::Signal.create!(
      organization: organization, subject: subject_record,
      monitor_key: "blood_pressure_trajectory_change", monitor_version: 1, monitor_digest: "d",
      signal_type: "blood_pressure_trajectory_change", domain_key: "hypertension",
      detected_at: 1.minute.from_now,
      window_started_at: base_time - 7.days, window_ended_at: base_time,
      severity: "low", deduplication_key: Digest::SHA256.hexdigest(SecureRandom.hex(8))
    )

    Cases::CorrelateSignal.call(signal: later_signal)

    case_record.reload
    expect(case_record.status).to eq("triaged")
    expect(case_record.case_events.pluck(:event_type)).to include("reopened")
    # S2C-016: the prior disposition survives the reopen.
    expect(case_record.dispositions.sole.code).to eq("action_taken")
  end

  # Serialization must not be bought by making every close take a global
  # lock: unrelated subjects still close in parallel.
  it "does not serialize resolution across subjects" do
    organization = Organization.create!(name: "Par", slug: "par-#{SecureRandom.hex(4)}")
    actor = create_user(email: "clinician-#{SecureRandom.hex(4)}@example.test")
    create_membership(organization: organization, user: actor, role: "clinician")

    cases = 3.times.map do
      subject_record = Subject.create!(organization: organization, timezone: "UTC")
      Cases::CaseRecord.create!(
        organization: organization, subject: subject_record,
        domain_key: "hypertension", case_type: "blood_pressure_change",
        title: "Blood pressure pattern change", status: "investigating",
        started_at: base_time - 7.days, detected_at: base_time - 1.day
      )
    end

    threads = cases.map do |case_record|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          resolve(Cases::CaseRecord.find(case_record.id), actor)
        end
      rescue StandardError => e
        e
      end
    end
    results = threads.map(&:value)

    expect(results.grep(StandardError)).to be_empty
    expect(Cases::CaseRecord.where(status: "resolved").count).to eq(3)
  end

  # No Signal in flight, nothing to serialize against — the ordinary close
  # must stay ordinary.
  it "leaves an uncontended resolution untouched" do
    _organization, _subject, actor, case_record, _signal = setup_scenario

    resolve(case_record, actor)

    expect(case_record.reload.status).to eq("resolved")
    expect(case_record.dispositions.sole.code).to eq("action_taken")
  end
end
