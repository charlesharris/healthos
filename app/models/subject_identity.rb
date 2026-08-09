# frozen_string_literal: true

# PHI for a Subject, encrypted at the application layer (HO §10.3).
#
# `deterministic: true` on the fields we must search by — without it the
# ciphertext differs per row and equality lookup is impossible. Deterministic
# encryption is weaker (equal plaintexts produce equal ciphertexts, so
# frequency analysis is possible), so it is used only where lookup is genuinely
# required. Names and dates of birth are non-deterministic.
class SubjectIdentity < ApplicationRecord
  belongs_to :organization
  belongs_to :subject

  encrypts :display_name
  encrypts :first_name
  encrypts :last_name
  encrypts :date_of_birth
  encrypts :contact_email, deterministic: true
  encrypts :contact_phone, deterministic: true

  validates :subject_id, uniqueness: true

  before_validation :inherit_organization

  # Safe for logs, error reports and job arguments — CLAUDE.md forbids PHI in
  # any of them. Anything that needs to name a subject in a technical context
  # uses this, never the identity fields.
  def technical_label = "subject:#{subject.public_id}"

  private

  def inherit_organization
    self.organization_id ||= subject&.organization_id
  end
end
