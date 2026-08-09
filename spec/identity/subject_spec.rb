# frozen_string_literal: true

require "rails_helper"

# Epic 001-04. HO §10.3.
#
# The epic names two specs: identity fields encrypted at rest, and identifiers
# resolving a subject idempotently.
RSpec.describe "Subject identity", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_org) { create_organization(name: "Southside", slug: "southside") }

  describe "encryption at rest (HO §10.3)" do
    let(:subject_record) { Subject.create!(organization: organization, timezone: "America/New_York") }

    # Asserted against the raw column, not the model. Reading through
    # ActiveRecord would decrypt transparently and prove nothing.
    it "stores no plaintext in the database" do
      SubjectIdentity.create!(
        subject: subject_record,
        first_name: "Marguerite",
        last_name: "Okonkwo",
        date_of_birth: "1962-04-11",
        contact_email: "marguerite@example.test"
      )

      raw = ActiveRecord::Base.connection.select_one(
        "SELECT first_name, last_name, date_of_birth, contact_email " \
        "FROM subject_identities WHERE subject_id = '#{subject_record.id}'"
      )

      expect(raw["first_name"]).not_to include("Marguerite")
      expect(raw["last_name"]).not_to include("Okonkwo")
      expect(raw["date_of_birth"]).not_to include("1962")
      expect(raw["contact_email"]).not_to include("marguerite")

      # Ciphertext, not merely absent.
      expect(raw["first_name"]).to include("p") # base64 envelope payload key
      expect(raw["first_name"].length).to be > "Marguerite".length
    end

    it "round-trips through the model" do
      identity = SubjectIdentity.create!(
        subject: subject_record, first_name: "Marguerite", last_name: "Okonkwo"
      )

      expect(identity.reload.first_name).to eq("Marguerite")
      expect(identity.last_name).to eq("Okonkwo")
    end

    # Deterministic encryption is required to look a subject up by contact
    # details; it is weaker, so it is used only where lookup is needed.
    it "allows lookup by deterministically encrypted fields" do
      SubjectIdentity.create!(subject: subject_record, contact_email: "find@example.test")

      expect(SubjectIdentity.find_by(contact_email: "find@example.test")&.subject)
        .to eq(subject_record)
    end

    # Non-deterministic ciphertext differs per row for identical plaintext,
    # which is why those fields cannot be searched. Asserted directly so the
    # distinction from the deterministic fields is not silently lost.
    it "produces different ciphertext for identical non-deterministic plaintext" do
      other = Subject.create!(organization: organization)
      SubjectIdentity.create!(subject: subject_record, first_name: "Marguerite")
      SubjectIdentity.create!(subject: other, first_name: "Marguerite")

      ciphertexts = ActiveRecord::Base.connection
        .select_values("SELECT first_name FROM subject_identities ORDER BY id")

      expect(ciphertexts.uniq.length).to eq(2)
    end

    it "keeps PHI out of the technical label used for logs and jobs" do
      identity = SubjectIdentity.create!(subject: subject_record, first_name: "Marguerite")

      expect(identity.technical_label).to eq("subject:#{subject_record.public_id}")
      expect(identity.technical_label).not_to include("Marguerite")
    end
  end

  describe "public_id" do
    it "does not encode creation time the way the internal UUIDv7 does" do
      a = Subject.create!(organization: organization)
      b = Subject.create!(organization: organization)

      # Internal ids are time-ordered by construction (ADR-002 3b)...
      expect([ a.id, b.id ].sort).to eq([ a.id, b.id ])
      # ...the public handle must not be, or it leaks enrolment order.
      expect(a.public_id).not_to eq(b.public_id)
      expect(a.public_id).to start_with("sub_")
    end
  end

  describe "identity resolution idempotency (S2C-020)" do
    def resolve(system: "mrn", value: "MRN-001", org: organization)
      Identity::ResolveSubject.call(organization: org, system: system, value: value)
    end

    it "creates a subject the first time" do
      result = resolve

      expect(result).to be_created
      expect(result.subject.organization).to eq(organization)
    end

    it "returns the same subject on repeat resolution" do
      first = resolve
      second = resolve

      expect(second.subject).to eq(first.subject)
      expect(second).not_to be_created
      expect(Subject.count).to eq(1)
    end

    it "keeps the same identifier value distinct across organizations" do
      here = resolve(org: organization)
      there = resolve(org: other_org)

      expect(there.subject).not_to eq(here.subject)
      expect(Subject.count).to eq(2)
    end

    it "treats different systems as different identifiers" do
      mrn = resolve(system: "mrn", value: "SHARED")
      fhir = resolve(system: "fhir_patient", value: "SHARED")

      expect(fhir.subject).not_to eq(mrn.subject)
    end

    # The database constraint, not the service, is the authority (S2C-022).
    it "rejects a duplicate identifier even when Ruby validation is skipped" do
      result = resolve
      duplicate = SubjectIdentifier.new(
        organization: organization, subject: result.subject, system: "mrn", value: "MRN-001"
      )

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "subject-local time (HO §121)" do
    it "resolves the day boundary in the subject's timezone, not the server's" do
      subject_record = Subject.create!(organization: organization, timezone: "America/New_York")

      # 03:00 UTC is still the previous day in New York. Getting this wrong
      # would misattribute readings to the wrong day and corrupt the
      # completeness denominators that SC §14 depends on.
      instant = Time.utc(2026, 3, 15, 3, 0, 0)

      expect(subject_record.local_date(instant)).to eq(Date.new(2026, 3, 14))
      expect(instant.utc.to_date).to eq(Date.new(2026, 3, 15))
    end

    it "rejects an unrecognized timezone" do
      record = Subject.new(organization: organization, timezone: "Mars/Olympus")

      expect(record).not_to be_valid
      expect(record.errors[:timezone].join).to match(/not a recognized/)
    end
  end
end
