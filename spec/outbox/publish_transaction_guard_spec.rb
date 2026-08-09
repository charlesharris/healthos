# frozen_string_literal: true

require "rails_helper"

# S2C-021. Isolated in its own file because proving this guard requires
# transactional fixtures to be off — otherwise the surrounding test
# transaction satisfies it trivially and the example asserts nothing.
#
# With fixtures off, anything created here commits for real, so setup and
# teardown are explicit.
RSpec.describe "Outbox.publish transaction guard", type: :model do
  self.use_transactional_tests = false

  let(:organization) do
    Organization.create!(name: "Guard Test", slug: "guard-#{SecureRandom.hex(4)}")
  end

  after do
    DomainEvent.where(organization_id: organization.id).delete_all
    organization.destroy
  end

  it "refuses to publish outside a transaction" do
    expect {
      Outbox.publish(
        organization: organization,
        aggregate: organization,
        event_type: "cases.case_created"
      )
    }.to raise_error(Outbox::NotInTransactionError, /inside a transaction/)
  end

  it "writes nothing when it refuses" do
    expect {
      begin
        Outbox.publish(
          organization: organization, aggregate: organization,
          event_type: "cases.case_created"
        )
      rescue Outbox::NotInTransactionError
        nil
      end
    }.not_to change(DomainEvent, :count)
  end

  it "publishes normally once a transaction is opened" do
    expect {
      ActiveRecord::Base.transaction do
        Outbox.publish(
          organization: organization, aggregate: organization,
          event_type: "cases.case_created"
        )
      end
    }.to change(DomainEvent, :count).by(1)
  end
end
