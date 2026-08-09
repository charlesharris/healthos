# frozen_string_literal: true

# Epic 001-02. Secure web sessions (HO §11 v0.1).
#
# Sessions belong to a user, not an organization. The active organization is
# resolved per-request from the user's memberships and held in Current, so a
# user with access to several organizations does not need separate sessions.
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :ip_address
      t.text :user_agent

      t.timestamps
    end
  end
end
