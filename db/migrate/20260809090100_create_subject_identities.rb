# frozen_string_literal: true

# Epic 001-04. HO §10.3: "Identity fields should use application-level
# encryption where appropriate."
#
# Split from `subjects` so the overwhelming majority of queries — telemetry,
# monitoring, analysis — never touch a table containing PHI. Reading identity
# is then a deliberate act, which is also what makes "Subject identity viewed"
# auditable as HO §92 requires.
class CreateSubjectIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :subject_identities, id: :uuid, default: -> { "uuidv7()" } do |t|
      # Denormalized per HO §10.1 even though reachable via subject.
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :subject, null: false, foreign_key: true, type: :uuid, index: { unique: true }

      # Encrypted at the application layer. Columns are text because
      # ciphertext is longer than plaintext and carries its own envelope.
      t.text :display_name
      t.text :first_name
      t.text :last_name
      t.text :date_of_birth
      t.text :contact_email
      t.text :contact_phone

      t.timestamps
    end
  end
end
