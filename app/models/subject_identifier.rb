# frozen_string_literal: true

# An external identifier for a Subject — FHIR Patient ID, MRN, RPM member id,
# device platform member id (HO §10.3).
#
# Not encrypted: an MRN is an identifier rather than clinical content, it must
# be indexed for resolution, and the uniqueness constraint that makes identity
# resolution idempotent has to operate on it. Its privacy classification is
# handled by access control and audit rather than by encryption.
class SubjectIdentifier < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  # The source_id column exists now so identifiers can record where they came
  # from, but the Source model arrives in 001-05. Declared then.
  # belongs_to :source, optional: true

  validates :system, :value, presence: true
  validates :value, uniqueness: { scope: %i[organization_id system] }

  before_validation :inherit_organization

  scope :for_system, ->(system) { where(system: system) }

  private

  def inherit_organization
    self.organization_id ||= subject&.organization_id
  end
end
