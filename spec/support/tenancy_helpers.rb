# frozen_string_literal: true

# Minimal builders for tenancy specs. Deliberately not FactoryBot yet — epic
# 001-02 needs four objects, and the synthetic data machinery that matters
# (spec/support/synthetic_health, HO §100) arrives in epic 003.
module TenancyHelpers
  def create_organization(name: "Northside Health", slug: nil, **attrs)
    slug ||= "org-#{SecureRandom.hex(4)}"
    Organization.create!(name: name, slug: slug, **attrs)
  end

  def create_user(email: nil, password: "correct horse battery staple", **attrs)
    User.create!(
      email_address: email || "user-#{SecureRandom.hex(4)}@example.test",
      password: password,
      **attrs
    )
  end

  def create_membership(organization:, user: nil, role: "clinician", **attrs)
    OrganizationMembership.create!(
      organization: organization,
      user: user || create_user,
      role: role,
      **attrs
    )
  end

  # Signs in through the real session controller so specs exercise the actual
  # authentication path rather than a test-only shortcut.
  def sign_in(user, password: "correct horse battery staple")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

RSpec.configure do |config|
  config.include TenancyHelpers
end
