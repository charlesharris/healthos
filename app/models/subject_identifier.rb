# frozen_string_literal: true

# An external identifier for a Subject — FHIR Patient ID, MRN, RPM member id,
# device platform member id (HO §10.3).
#
# DETERMINISTICALLY ENCRYPTED, reversing the 001-04 decision.
#
# The original reasoning was that an identifier must stay plaintext because it
# has to be indexed for resolution and carry the uniqueness constraint that
# makes identity resolution idempotent. That was wrong on the facts:
# deterministic encryption produces stable ciphertext, so equality lookup and
# the unique index both keep working — it is the same trade already accepted
# for contact_email.
#
# What the original reasoning missed is that ActiveRecord logs SQL, so an
# unencrypted MRN appears in plaintext in every INSERT and SELECT that touches
# this table. HO §93's list of what technical logs may contain does not include
# external identifiers, and an MRN is a direct handle on a person. Found by
# spec/security/phi_leakage_spec.rb rather than by review.
class SubjectIdentifier < ApplicationRecord
  belongs_to :organization
  belongs_to :subject
  belongs_to :source, optional: true

  # Deterministic so the unique index over (organization, system, value) still
  # enforces uniqueness of the PLAINTEXT, and so ResolveSubject can look an
  # identifier up by equality. Weaker than non-deterministic encryption, and
  # the right trade here: without lookup the column cannot do its job.
  encrypts :value, deterministic: true

  validates :system, :value, presence: true
  validates :value, uniqueness: { scope: %i[organization_id system] }

  before_validation :inherit_organization

  scope :for_system, ->(system) { where(system: system) }

  private

  def inherit_organization
    self.organization_id ||= subject&.organization_id
  end
end
