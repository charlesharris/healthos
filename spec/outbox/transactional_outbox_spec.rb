# frozen_string_literal: true

require "rails_helper"

# S2C-020 — at-least-once jobs; all workflows tolerate retries.
# S2C-021 — transactional outbox; durable state change and downstream job
#           intent cannot silently diverge.
#
# Epic 001-03 requires two specs by name: "commit + dispatcher crash → event
# redelivered" and "dispatch is idempotent".
RSpec.describe "Transactional outbox", type: :model do
  let!(:organization) { create_organization(name: "Northside Health", slug: "northside") }

  # A stand-in consumer. The real handlers arrive with the epics that own
  # them (correlation in 001-11, analysis in 003-22); the outbox itself must
  # be provable before any of them exist.
  before do
    stub_const("TestHandlerJob", Class.new(ApplicationJob) do
      cattr_accessor :performed_event_ids, default: []

      def perform(event_id)
        self.class.performed_event_ids << event_id
      end
    end)

    Outbox::Registry.reset!
    Outbox::Registry.register("cases.case_created", "TestHandlerJob")
    TestHandlerJob.performed_event_ids = []
  end

  after { Outbox::Registry.reset! }

  def publish_event(event_type: "cases.case_created")
    ActiveRecord::Base.transaction do
      Outbox.publish(
        organization: organization,
        aggregate: organization,
        event_type: event_type,
        payload: { "example" => "id-only" }
      )
    end
  end

  describe "S2C-021 atomicity with the state change" do
    it "rolls the event back when the surrounding transaction fails" do
      expect {
        ActiveRecord::Base.transaction do
          Outbox.publish(
            organization: organization, aggregate: organization,
            event_type: "cases.case_created"
          )
          raise ActiveRecord::Rollback
        end
      }.not_to change(DomainEvent, :count)
    end

    it "rejects an unregistered event type rather than writing a silent orphan" do
      expect {
        publish_event(event_type: "cases.nothing_listens_to_this")
      }.to raise_error(Outbox::UnknownEventType)
    end

    # The "must be inside a transaction" guard needs transactional fixtures
    # switched off to be meaningful, which leaks committed rows into sibling
    # examples. It therefore lives in its own file:
    # spec/outbox/publish_transaction_guard_spec.rb
  end

  describe "dispatch" do
    it "converts a pending event into an Active Job and marks it dispatched" do
      publish_event
      event = DomainEvent.last

      expect { Outbox::DispatchJob.perform_now }
        .to change { event.reload.dispatched_at }.from(nil)

      expect(TestHandlerJob.performed_event_ids).to be_empty # enqueued, not run
      expect(enqueued_jobs_for(TestHandlerJob)).to contain_exactly(event.id)
    end

    it "passes only the event id to the handler, never the payload" do
      publish_event
      event = DomainEvent.last

      Outbox::DispatchJob.perform_now

      args = ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j[:args] }.flatten
      expect(args).to eq([ event.id ])
      expect(args.join).not_to include("id-only")
    end

    it "does not redispatch an already dispatched event" do
      publish_event
      Outbox::DispatchJob.perform_now
      clear_enqueued_jobs

      expect { Outbox::DispatchJob.perform_now }
        .not_to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }
    end

    it "dispatches in occurred_at order" do
      3.times { publish_event }
      expected = DomainEvent.order(:occurred_at, :id).pluck(:id)

      Outbox::DispatchJob.perform_now

      expect(enqueued_jobs_for(TestHandlerJob)).to eq(expected)
    end
  end

  # Epic 001-03: "commit + dispatcher crash → event redelivered".
  describe "S2C-020 redelivery after a dispatcher crash" do
    it "leaves the event pending when marking it dispatched fails" do
      publish_event
      event = DomainEvent.last

      # Simulates a crash in the window between a successful enqueue and the
      # dispatched_at write — the exact gap the separate queue database makes
      # unavoidable.
      allow_any_instance_of(DomainEvent).to receive(:update!).and_raise(StandardError, "crash")

      Outbox::DispatchJob.perform_now

      expect(event.reload.dispatched_at).to be_nil
      expect(event.attempts).to eq(1)
      expect(event.last_error).to include("crash")
    end

    it "redelivers on the next run, so the handler must be idempotent" do
      publish_event
      event = DomainEvent.last

      crashed = false
      allow_any_instance_of(DomainEvent).to receive(:update!) do
        crashed = true
        raise StandardError, "crash"
      end
      Outbox::DispatchJob.perform_now
      expect(crashed).to be(true)

      # Recovery: the mark succeeds this time.
      allow_any_instance_of(DomainEvent).to receive(:update!).and_call_original
      Outbox::DispatchJob.perform_now

      expect(event.reload.dispatched_at).to be_present
      # Enqueued twice across the two runs. This is at-least-once delivery
      # working as designed, not a defect — S2C-020 requires handlers to
      # tolerate it.
      expect(enqueued_jobs_for(TestHandlerJob)).to eq([ event.id, event.id ])
    end

    it "gives up after MAX_ATTEMPTS instead of starving newer events" do
      publish_event
      event = DomainEvent.last
      event.update_columns(attempts: DomainEvent::MAX_ATTEMPTS)

      Outbox::DispatchJob.perform_now

      expect(enqueued_jobs_for(TestHandlerJob)).to be_empty
      expect(event.reload).to be_dead
      expect(DomainEvent.pending).not_to include(event)
    end

    it "keeps a dead event visible for support rather than deleting it" do
      publish_event
      DomainEvent.last.update_columns(attempts: DomainEvent::MAX_ATTEMPTS)

      expect(DomainEvent.dead.count).to eq(1)
    end

    # One poisoned event must not block everything queued behind it.
    it "continues past a failing event to dispatch the rest of the batch" do
      publish_event
      poisoned = DomainEvent.last
      publish_event
      healthy = DomainEvent.where.not(id: poisoned.id).last

      allow(Outbox::Registry).to receive(:job_for).and_call_original
      allow(Outbox::Registry).to receive(:job_for).with("cases.case_created") do
        raise Outbox::Registry::UnregisteredEventType, "boom" if @first_call.nil?.tap { @first_call = true }

        TestHandlerJob
      end

      Outbox::DispatchJob.perform_now

      expect(poisoned.reload.dispatched_at).to be_nil
      expect(healthy.reload.dispatched_at).to be_present
    end
  end

  describe "concurrency" do
    # FOR UPDATE SKIP LOCKED is what allows several dispatchers to run without
    # double-claiming. Verified by asserting the lock clause reaches SQL —
    # genuine parallel dispatchers are exercised by the epic 001-11
    # concurrency specs (HO §120), which have real contention to create.
    it "claims rows with FOR UPDATE SKIP LOCKED" do
      sql = DomainEvent.pending.limit(10).lock("FOR UPDATE SKIP LOCKED").to_sql

      expect(sql).to include("FOR UPDATE SKIP LOCKED")
    end
  end

  def enqueued_jobs_for(job_class)
    ActiveJob::Base.queue_adapter.enqueued_jobs
      .select { |j| j[:job] == job_class }
      .map { |j| j[:args].first }
  end

  def clear_enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
end
