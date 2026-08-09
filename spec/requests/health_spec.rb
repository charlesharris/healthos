# frozen_string_literal: true

require "rails_helper"

# Epic 001-01: "Health endpoint + one passing request spec".
#
# Rails provides /up as a liveness check. What this spec is really proving at
# this point in the epic is that the whole stack boots against the three-role
# database setup — the request cycle runs as healthos_app, not as an owner or
# superuser (ADR-002 Decision 4a-iv).
RSpec.describe "Health", type: :request do
  describe "GET /up" do
    it "returns 200 when the application boots" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "database identity" do
    it "connects as the unprivileged application role" do
      current_user = ActiveRecord::Base.connection.select_value("SELECT current_user")

      expect(current_user).to eq("healthos_app")
    end

    it "is not a superuser and cannot bypass privilege checks" do
      superuser = ActiveRecord::Base.connection.select_value(
        "SELECT usesuper FROM pg_user WHERE usename = current_user"
      )

      expect(superuser).to be(false)
    end
  end
end
