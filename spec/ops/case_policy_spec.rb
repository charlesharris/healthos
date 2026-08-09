# frozen_string_literal: true

require "rails_helper"

# The Ops Queue is health data, not operational metadata: a Case names a
# subject, states why the system thinks something changed, and links to the
# readings behind it.
#
# HO §11 lists support_limited as a role and HO §157 wants support access to
# be "provider-safe" and audited. Until 005-15 builds that surface, support
# staff do not read the queue.
#
# This closes a gap inherited from the v0 queue, which authorized on
# OrganizationPolicy#show? — any active membership.
RSpec.describe "Ops Queue authorization", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }

  before do
    Cases::CaseRecord.create!(
      organization: organization, subject: subject_record,
      domain_key: "hypertension", case_type: "blood_pressure_change",
      title: "Blood pressure pattern change", status: "new",
      started_at: 7.days.ago, detected_at: 1.day.ago
    )
  end

  def sign_in_with(role)
    user = create_user(email: "#{role}@example.test")
    create_membership(organization: organization, user: user, role: role)
    sign_in user
    user
  end

  OrganizationMembership::CLINICAL_ROLES.each do |role|
    it "admits #{role}" do
      sign_in_with(role)
      get ops_cases_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Blood pressure pattern change")
    end
  end

  # The role HO §11 defines precisely so that support can exist without
  # clinical visibility. Admitting it here would make the distinction
  # decorative.
  it "refuses support_limited" do
    sign_in_with("support_limited")
    get ops_cases_path

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Blood pressure pattern change")
  end

  it "refuses support_limited on Quick Review too" do
    sign_in_with("support_limited")
    get ops_case_path(Cases::CaseRecord.sole)

    expect(response).to have_http_status(:not_found)
  end

  it "refuses a suspended clinical membership" do
    user = create_user(email: "suspended@example.test")
    create_membership(organization: organization, user: user, role: "clinician", status: "suspended")

    sign_in user
    get ops_cases_path

    # A suspended membership grants nothing, which the policy inherits from
    # ApplicationPolicy#active?.
    expect(response).not_to have_http_status(:ok)
  end

  describe "the policy itself" do
    it "treats reading the queue as clinical access" do
      membership = create_membership(organization: organization, role: "support_limited")
      policy = CasePolicy.new(membership: membership, record: organization)

      expect(policy.show?).to be(false)
      expect(policy.index?).to be(false)
      # Changing state and assigning are clinical acts, not merely reads.
      expect(policy.transition?).to be(false)
      expect(policy.assign?).to be(false)
    end

    it "matches the membership's own clinical-access definition" do
      OrganizationMembership::ROLES.each do |role|
        membership = create_membership(organization: organization, role: role)
        policy = CasePolicy.new(membership: membership, record: organization)

        # One definition of clinical access, not two that can drift apart.
        expect(policy.show?).to eq(membership.clinical_access?)
      end
    end
  end
end
