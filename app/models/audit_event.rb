# frozen_string_literal: true

# Provider and staff access audit (HO §92). Append-only (INV-26): the app role
# can INSERT and SELECT, never UPDATE or DELETE — enforced by grant, not by
# convention (ADR-002 Decision 4a).
#
# Deliberately separate from technical logging (HO §93). This table answers
# "who looked at what", which is an evidence question; logs answer "what did
# the system do", which is an operations question.
class AuditEvent < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :actor, class_name: "User"
  belongs_to :staff_member, optional: true

  validates :event_type, :occurred_at, presence: true

  scope :by_actor, ->(user) { where(actor_id: user.id) }
  scope :recent, -> { order(occurred_at: :desc) }

  # "Avoid raw PHI in audit metadata unless required" (HO §92). Callers pass
  # identifiers and field names, never values.
  def self.record!(event_type:, actor:, organization: nil, staff_member: nil, metadata: {})
    create!(
      event_type: event_type,
      actor: actor,
      organization: organization,
      staff_member: staff_member,
      occurred_at: Time.current,
      metadata: metadata
    )
  end
end
