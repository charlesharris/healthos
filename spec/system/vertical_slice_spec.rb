# frozen_string_literal: true

require "rails_helper"

# Epic 001-13 — the Definition of Done, as one spec.
#
#   POST synthetic BP data (twice, identical payload)
#   → one RawEnvelope (append-only, raw payload in object storage)
#   → canonical BP ObservationGroup + Observations with provenance
#   → daily BP derived summary with lineage
#   → one trajectory Signal (retry does not duplicate)
#   → exactly one blood_pressure_change Case (concurrent correlation safe)
#   → CaseEvent timeline
#   → authenticated operator sees the Case in the Ops Queue
#
# Deliberately end-to-end and deliberately not mocked between stages: the
# point of a vertical slice is to prove the seams hold, and every stage
# boundary here is a place where an invariant could quietly fail.
RSpec.describe "Vertical slice", type: :request do
  let!(:organization) { create_organization(name: "Northside Health", slug: "northside") }
  let!(:operator) { create_user(email: "operator@example.test") }
  let!(:membership) { create_membership(organization: organization, user: operator, role: "clinical_ops") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP feed")
  end

  let(:store) { Storage::RawPayloadStore.instance }
  let(:as_of) { Time.utc(2026, 3, 22, 12, 0) }

  before do
    store.client.head_bucket(bucket: store.bucket)
  rescue StandardError => e
    skip "object storage unavailable (#{e.class}) — run `docker compose up -d minio`"
  end

  def payload_for(day_offset:, systolic:, diastolic: 84, pulse: 70)
    recorded = as_of - day_offset.days
    {
      subject_identifier: { system: "mrn", value: "MRN-SLICE-001" },
      recorded_at: recorded.iso8601,
      systolic: systolic, diastolic: diastolic, pulse: pulse,
      recording_method: "device_automatic"
    }.to_json
  end

  # Ingest → normalize, the way production does it: through the outbox.
  def ingest_and_normalize(day_offset:, systolic:)
    envelope = Ingestion::Receive.call(
      source: source, payload: payload_for(day_offset: day_offset, systolic: systolic),
      source_record_id: "bp-#{day_offset}", store: store
    ).envelope

    Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)
    envelope
  end

  it "carries synthetic BP data through the whole pipeline to a visible queue row" do
    # ---- Stage 1: ingestion, twice with an identical payload (S2C-020) ----
    first = Ingestion::Receive.call(
      source: source, payload: payload_for(day_offset: 1, systolic: 142),
      source_record_id: "bp-1", store: store
    )
    second = Ingestion::Receive.call(
      source: source, payload: payload_for(day_offset: 1, systolic: 142),
      source_record_id: "bp-1", store: store
    )

    expect(first).to be_created
    expect(second).not_to be_created
    expect(RawEnvelope.count).to eq(1), "duplicate POST created a second envelope"

    envelope = first.envelope
    expect(envelope.payload(store: store)).to include("142")

    # ---- Stage 2: canonical telemetry with provenance ----
    Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)

    expect(ObservationGroup.count).to eq(1)
    expect(Observation.count).to eq(3) # systolic, diastolic, pulse — one unit

    subject_record = Subject.sole
    systolic = Observation.find_by(semantic_key: "health.vital.blood_pressure.systolic")
    expect(systolic.value_numeric).to eq(142)
    expect(systolic.provenance[:raw_envelope_id]).to eq(envelope.id)
    expect(systolic.provenance[:normalizer]).to eq("synthetic_bp_json@v1")

    # ---- Stage 3: a population with a genuine trajectory change ----
    # Baseline 120s, then a recent run of 142s.
    (8..20).each { |d| ingest_and_normalize(day_offset: d, systolic: 120) }
    (2..6).each { |d| ingest_and_normalize(day_offset: d, systolic: 142) }

    (1..20).each do |d|
      Derivation::ComputeDailySummary.call(
        subject: subject_record,
        semantic_key: "health.vital.blood_pressure.systolic",
        date: (as_of - d.days).to_date
      )
    end

    summaries = DerivedSignal.computed
    expect(summaries.count).to be >= 15

    # Lineage resolves to the exact observations (INV-3).
    sample = summaries.first
    expect(sample.inputs).to all(be_a(Observation))
    expect(sample.evidence_set.purpose).to eq("derived_signal_inputs")

    # ---- Stage 4: monitor → Signal, and a retry does not duplicate ----
    result = Monitoring::EvaluateMonitor.call(
      subject: subject_record, monitor_key: "blood_pressure_trajectory_change", as_of: as_of
    )
    expect(result).to be_triggered

    retry_result = Monitoring::EvaluateMonitor.call(
      subject: subject_record, monitor_key: "blood_pressure_trajectory_change", as_of: as_of
    )
    expect(retry_result).not_to be_created
    expect(Monitoring::Signal.count).to eq(1), "monitor retry duplicated the Signal (S2C-002)"

    signal = result.signal
    expect(signal.attributes_json["direction"]).to eq("increase")

    # ---- Stage 5: correlation → exactly one Case ----
    correlation = Cases::CorrelateSignal.call(signal: signal)

    expect(correlation).to be_created
    expect(Cases::CaseRecord.count).to eq(1)

    case_record = correlation.case_record
    expect(case_record.case_type).to eq("blood_pressure_change")
    expect(case_record.subject).to eq(subject_record)

    # ---- Stage 6: CaseEvent timeline ----
    expect(case_record.case_events.pluck(:event_type)).to include("case_created")
    expect(Cases::CaseEvent.chain_intact?(case_record)).to be(true)

    # ---- Stage 7: an authenticated operator sees it in the queue ----
    sign_in operator
    get ops_cases_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Blood pressure pattern change")
    # HO §84: subject identity is secondary and opaque — the queue shows a
    # public handle, never a name.
    expect(response.body).to include(subject_record.public_id)
    expect(response.body).not_to include("MRN-SLICE-001")
  end

  it "keeps the whole chain drillable back to the stored bytes" do
    envelope = ingest_and_normalize(day_offset: 1, systolic: 142)
    observation = Observation.find_by(semantic_key: "health.vital.blood_pressure.systolic")

    # INV-4/5: every provider-facing value traces down to source records, and
    # the bytes are verified rather than trusted on the way (ADR-002 4b).
    expect(observation.raw_envelope).to eq(envelope)
    expect(observation.raw_envelope.payload(store: store)).to include("142")
  end

  it "denies the queue to a user from another organization" do
    other_org = create_organization(name: "Southside", slug: "southside")
    outsider = create_user(email: "outsider@example.test")
    create_membership(organization: other_org, user: outsider, role: "clinical_ops")

    envelope = ingest_and_normalize(day_offset: 1, systolic: 142)
    subject_record = envelope.observations.first.subject
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      started_at: as_of - 7.days, detected_at: as_of
    )

    sign_in outsider
    get ops_cases_path

    # INV-31: the outsider sees their own (empty) queue, never Northside's.
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Blood pressure pattern change")
  end
end
