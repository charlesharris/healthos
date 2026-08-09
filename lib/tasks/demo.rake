# frozen_string_literal: true

# Demo seed (HO §127, epic 001-13). Synthetic only — prototype-scope.md
# records that this system holds no real data.
#
# v0 deliberately small: a handful of subjects, one with a genuine trajectory
# change. HO §127's full population (100+ subjects, instrumentation changes,
# false alarms, reopened and watching Cases) arrives with the epic 002 gate,
# once there are lifecycle states worth seeding.
namespace :demo do
  desc "Seed a small synthetic population with one trajectory change"
  task seed: :environment do
    org = Organization.find_or_create_by!(slug: "demo-health") { |o| o.name = "Demo Health" }

    source = Source.find_or_create_by!(organization: org, key: "synthetic-bp") do |s|
      s.source_type = "synthetic"
      s.display_name = "Synthetic BP feed"
    end

    as_of = Time.current.beginning_of_hour
    store = Storage::RawPayloadStore.instance

    # Ground truth is stated here so the demo is interpretable: someone
    # reading the queue should be able to check whether the system found what
    # was actually injected.
    population = [
      { mrn: "DEMO-001", label: "genuine rise", baseline: 122, recent: 145 },
      { mrn: "DEMO-002", label: "stable", baseline: 118, recent: 119 },
      { mrn: "DEMO-003", label: "stable", baseline: 128, recent: 127 },
      { mrn: "DEMO-004", label: "genuine fall", baseline: 140, recent: 118 }
    ]

    population.each do |person|
      puts "  #{person[:mrn]} (#{person[:label]})"

      (1..21).each do |days_ago|
        systolic = days_ago <= 6 ? person[:recent] : person[:baseline]
        # A little variation so medians are not degenerate. Seeded per subject
        # and day, so re-running the seed reproduces the same population.
        rng = Random.new(Digest::SHA256.hexdigest("#{person[:mrn]}:#{days_ago}").to_i(16) % 2**32)
        systolic += rng.rand(-4..4)

        payload = {
          subject_identifier: { system: "mrn", value: person[:mrn] },
          recorded_at: (as_of - days_ago.days).iso8601,
          systolic: systolic, diastolic: systolic - 58, pulse: 68 + rng.rand(-5..5),
          recording_method: "device_automatic"
        }.to_json

        envelope = Ingestion::Receive.call(
          source: source, payload: payload,
          source_record_id: "#{person[:mrn]}-#{days_ago}", store: store
        ).envelope

        Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)
      end
    end

    puts "\n== Deriving daily summaries =="
    Subject.where(organization: org).find_each do |subject|
      (1..21).each do |days_ago|
        Derivation::ComputeDailySummary.call(
          subject: subject, semantic_key: "health.vital.blood_pressure.systolic",
          date: (as_of - days_ago.days).to_date
        )
      end
    end

    puts "== Running monitors =="
    Subject.where(organization: org).find_each do |subject|
      result = Monitoring::EvaluateMonitor.call(
        subject: subject, monitor_key: "blood_pressure_trajectory_change", as_of: as_of
      )
      next unless result.triggered?

      Cases::CorrelateSignal.call(signal: result.signal)
    end

    puts "\n== Seeded =="
    puts "  subjects:     #{Subject.where(organization: org).count}"
    puts "  observations: #{Observation.where(organization: org).count}"
    puts "  signals:      #{Monitoring::Signal.where(organization: org).count}"
    puts "  cases:        #{Cases::CaseRecord.where(organization: org).count}"
    puts "\n  Expect Cases for DEMO-001 and DEMO-004 only. A Case for DEMO-002"
    puts "  or DEMO-003 would be a false positive worth investigating."
  end

  desc "Re-run normalization for one envelope: rake 'demo:replay[env_public_id]'"
  task :replay, [ :public_id ] => :environment do |_t, args|
    envelope = RawEnvelope.find_by!(public_id: args[:public_id])

    puts "Replaying #{envelope.public_id} (#{envelope.adapter_key}@v#{envelope.adapter_version})"
    result = Normalization::NormalizeEnvelope.call(envelope: envelope)

    if result.created?
      puts "  normalized: #{result.observations.size} observation(s)"
    else
      # HO §96: re-running the same normalizer version is a no-op by design.
      # New rows require a new version (HO §155).
      puts "  no-op (#{result.skipped_reason}) — already normalized at this normalizer version"
    end
  end
end
