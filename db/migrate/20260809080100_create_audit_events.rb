# frozen_string_literal: true

# Provider and staff access audit (HO §92), pulled forward from epic 002-24.
#
# Brought forward because the admin UI lands now with write access, and HO §92
# lists "Admin configuration changed" as an auditable event while HO §157
# requires support access to be audited. Shipping admin writes before the
# audit table would have left them unauditable by construction. 002-24 extends
# this with the case/investigation events; the table is per §92 as written.
#
# Append-only (INV-26). Classified as such in db/privileges.yml, so the app
# role can INSERT and SELECT but never UPDATE or DELETE.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events, id: :uuid, default: -> { "uuidv7()" } do |t|
      # DEVIATION from §92, which implies NOT NULL by marking only subject_id,
      # case_id and investigation_id nullable. Platform-level staff actions
      # genuinely have no tenant — editing a User, which is global by HO §10.2,
      # is the clearest case. Nullable with an explicit reason beats inventing
      # a sentinel organization.
      t.references :organization, foreign_key: true, type: :uuid

      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.text :event_type, null: false

      t.references :subject, type: :uuid, index: false
      t.references :case, type: :uuid, index: false
      t.references :investigation, type: :uuid, index: false

      # Set when the actor is acting as platform staff rather than as a member
      # of the organization, so the two access paths stay distinguishable in
      # the audit trail.
      t.references :staff_member, type: :uuid, foreign_key: true

      t.datetime :occurred_at, null: false

      # "Avoid raw PHI in audit metadata unless required" (HO §92).
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :audit_events, [ :organization_id, :occurred_at ],
      name: "index_audit_events_on_org_and_time"
    add_index :audit_events, [ :actor_id, :occurred_at ],
      name: "index_audit_events_on_actor_and_time"
    add_index :audit_events, [ :event_type, :occurred_at ],
      name: "index_audit_events_on_type_and_time"
  end
end
