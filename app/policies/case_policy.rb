# frozen_string_literal: true

# Authorization for the Ops Queue and Quick Review.
#
# The queue is health data. A Case names a subject, states why the system
# thinks something changed, and links to the readings behind it — so reading
# it is reading clinical evidence, not operational metadata.
#
# HO §11 lists `support_limited` as a role, and HO §157 wants support access
# to be "provider-safe" and audited. `OrganizationMembership::CLINICAL_ROLES`
# already excludes support_limited for exactly this reason; until 005-15
# builds a genuinely provider-safe support surface, support staff do not read
# the queue at all.
#
# This closes a gap inherited from the v0 queue, which authorized on
# `OrganizationPolicy#show?` — any active membership. That was too broad, and
# was flagged rather than silently widened when the queue UI was built.
class CasePolicy < ApplicationPolicy
  def show? = active? && membership.clinical_access?
  def index? = show?

  # Changing state and assigning are clinical acts, not merely read access.
  def transition? = show?
  def assign? = show?
end
