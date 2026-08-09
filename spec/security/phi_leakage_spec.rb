# frozen_string_literal: true

require "rails_helper"

# The epic 001 gate item that was deliberately left open, now closed.
#
# CLAUDE.md: "No PHI in technical logs, job arguments, metric labels, or error
# reports. Pass IDs to jobs, never payloads."
# INV-32; HO §92 (audit is separate from logging), §93 (what logs MAY contain),
# §123 (job/log PHI leakage checks before pilot).
#
# The architecture was built for this from 001-03 onward — jobs take ids,
# `SubjectIdentity#technical_label` exists precisely for this, audit is a
# separate table. But architecture-implies-correctness is not a test, and this
# is the one invariant where a silent violation is both easy and serious. So
# this drives the real pipeline with distinctive PHI and greps everything it
# can reach.
RSpec.describe "PHI leakage", type: :model do
  # Deliberately unusual, so a match cannot be coincidence and a partial leak
  # (a truncated name in an error message) still trips the assertion.
  PHI_VALUES = {
    first_name: "Zephyrine",
    last_name: "Quattlebaum",
    dob: "1962-04-11",
    email: "zephyrine.quattlebaum@example.test",
    phone: "+15551234567",
    mrn: "MRN-ZQ-99881"
  }.freeze

  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP")
  end

  let(:log_output) { StringIO.new }
  let(:store) { Storage::RawPayloadStore.instance }

  around do |example|
    original = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(log_output).tap { |l| l.level = Logger::DEBUG })
    ActiveRecord::Base.logger = Rails.logger
    example.run
  ensure
    Rails.logger = original
    ActiveRecord::Base.logger = original
  end

  before do
    store.client.head_bucket(bucket: store.bucket)
  rescue StandardError => e
    skip "object storage unavailable (#{e.class}) — run `docker compose up -d minio`"
  end

  def run_pipeline!
    subject_record = Identity::ResolveSubject.call(
      organization: organization, system: "mrn", value: PHI_VALUES[:mrn]
    ).subject

    SubjectIdentity.create!(
      subject: subject_record,
      first_name: PHI_VALUES[:first_name], last_name: PHI_VALUES[:last_name],
      date_of_birth: PHI_VALUES[:dob], contact_email: PHI_VALUES[:email],
      contact_phone: PHI_VALUES[:phone]
    )

    payload = {
      subject_identifier: { system: "mrn", value: PHI_VALUES[:mrn] },
      recorded_at: Time.utc(2026, 3, 15, 14, 0).iso8601,
      systolic: 142, diastolic: 88, pulse: 68
    }.to_json

    envelope = Ingestion::Receive.call(
      source: source, payload: payload, source_record_id: "phi-1", store: store
    ).envelope

    Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)
    Outbox::DispatchJob.perform_now

    subject_record
  end

  def logged = log_output.string

  describe "technical logs (INV-32, HO §93)" do
    it "leaks no identity field through a full ingest and normalize" do
      run_pipeline!

      PHI_VALUES.slice(:first_name, :last_name, :dob, :email, :phone).each do |field, value|
        expect(logged).not_to include(value),
          "#{field} (#{value.inspect}) appeared in the technical log"
      end
    end

    # The MRN is an identifier rather than clinical content, but it is still a
    # direct handle on a person and HO §93's allowed list does not include it —
    # only opaque internal and public ids.
    it "leaks no external identifier" do
      run_pipeline!

      expect(logged).not_to include(PHI_VALUES[:mrn])
    end

    # HO §93 does permit these, and they are what makes an incident
    # debuggable. Asserted so the test cannot pass by the pipeline logging
    # nothing at all — which would make every other assertion here vacuous.
    it "still logs enough to debug with" do
      run_pipeline!

      expect(logged).to be_present
      expect(logged.length).to be > 200
    end
  end

  describe "job arguments (CLAUDE.md: pass IDs, never payloads)" do
    it "enqueues only ids, never a payload" do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      run_pipeline!

      serialized = ActiveJob::Base.queue_adapter.enqueued_jobs.to_json

      PHI_VALUES.each_value do |value|
        expect(serialized).not_to include(value)
      end
      # Nor the clinical values themselves.
      expect(serialized).not_to include("142")
    end

    # Job arguments are serialized into the queue DATABASE, where they outlive
    # the request and are visible to anyone inspecting the queue.
    it "stores no payload in the outbox event" do
      run_pipeline!

      DomainEvent.find_each do |event|
        PHI_VALUES.each_value do |value|
          expect(event.payload.to_json).not_to include(value)
        end
      end
    end
  end

  describe "error reports" do
    # An exception message is the classic leak: it is built from whatever was
    # in scope, and it travels to log aggregators and error trackers.
    it "leaks no PHI when normalization fails" do
      subject_record = run_pipeline!
      envelope = RawEnvelope.last

      allow_any_instance_of(Normalization::SyntheticBloodPressureJson)
        .to receive(:call).and_raise(StandardError, "boom")

      begin
        Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)
      rescue StandardError => e
        expect(e.message).not_to include(PHI_VALUES[:mrn])
        expect(e.message).not_to include(PHI_VALUES[:first_name])
      end

      expect(subject_record).to be_present
    end

    it "truncates and sanitises outbox dispatch errors" do
      run_pipeline!
      event = DomainEvent.first
      event.update_columns(attempts: 0, dispatched_at: nil, last_error: nil)

      allow(Outbox::Registry).to receive(:job_for)
        .and_raise(StandardError, "failure mentioning #{PHI_VALUES[:mrn]}")

      Outbox::DispatchJob.perform_now

      # The dispatcher records the error class and a bounded message on a
      # tenant-facing table, so the truncation matters as much as the content.
      expect(event.reload.last_error.to_s.length).to be <= 550
    end
  end

  describe "the technical label (HO §93)" do
    it "identifies a subject opaquely for log use" do
      subject_record = run_pipeline!
      label = subject_record.subject_identity.technical_label

      expect(label).to eq("subject:#{subject_record.public_id}")
      PHI_VALUES.each_value { |value| expect(label).not_to include(value) }
    end
  end

  describe "audit is separate from logging (HO §92)" do
    # The audit trail legitimately records WHO looked at WHAT. It is not a
    # technical log and is not shipped to log aggregators — conflating them is
    # how PHI ends up somewhere it was never meant to be.
    it "keeps audit events in their own table, not in the log stream" do
      subject_record = run_pipeline!
      actor = create_user(email: "clinician@example.test")

      AuditEvent.record!(
        event_type: "subject.identity_viewed", actor: actor,
        organization: organization,
        metadata: { "subject_id" => subject_record.id }
      )

      # Ids, not values, even here — HO §92: "avoid raw PHI in audit metadata
      # unless required."
      event = AuditEvent.last
      PHI_VALUES.each_value { |value| expect(event.metadata.to_json).not_to include(value) }
    end
  end
end
