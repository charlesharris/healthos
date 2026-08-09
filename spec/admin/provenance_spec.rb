# frozen_string_literal: true

require "rails_helper"

# Epic 001-08: "Admin provenance drilldown view: canonical BP → raw envelope
# → stored payload." HO §21, §92, §157; INV-4, INV-5.
RSpec.describe "Admin provenance drilldown", type: :request do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:staff_user) { create_user(email: "staff@example.test") }
  let!(:staff) { StaffMember.create!(user: staff_user, status: "active") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP")
  end

  let(:payload) do
    { subject_identifier: { system: "mrn", value: "MRN-001" },
      recorded_at: "2026-03-15T14:00:00Z",
      systolic: 142, diastolic: 88, pulse: 68 }.to_json
  end

  let(:store) { Storage::RawPayloadStore.instance }

  let(:observation) do
    envelope = Ingestion::Receive.call(
      source: source, payload: payload, source_record_id: "bp-001", store: store
    ).envelope
    Normalization::NormalizeEnvelope.call(envelope: envelope, store: store)
    Observation.find_by(semantic_key: "health.vital.blood_pressure.systolic")
  end

  before do
    store.client.head_bucket(bucket: store.bucket)
  rescue StandardError => e
    skip "object storage unavailable (#{e.class}) — run `docker compose up -d minio`"
  end

  describe "access" do
    it "requires platform staff" do
      plain = create_user(email: "plain@example.test")
      create_membership(organization: organization, user: plain, role: "organization_admin")
      target = observation

      sign_in plain
      get admin_provenance_path(target)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "drilldown" do
    before { sign_in staff_user }

    it "shows the canonical value, its provenance, and the stored payload" do
      get admin_provenance_path(observation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("health.vital.blood_pressure.systolic")
      expect(response.body).to include("142")
      # Provenance chain: normalizer, envelope, and the raw bytes themselves.
      expect(response.body).to include("synthetic_bp_json@v1")
      expect(response.body).to include(observation.raw_envelope.content_hash)
      expect(response.body).to include("Integrity verified")
      expect(response.body).to include("&quot;systolic&quot;:142").or include('"systolic":142')
    end

    it "links the observations measured together" do
      get admin_provenance_path(observation)

      # One cuff inflation, three readings — the sibling links are what make
      # the analytical unit visible rather than implied.
      expect(response.body).to include("health.vital.pulse")
      expect(response.body).to include("Measured together")
    end

    # A drilldown that silently rendered altered evidence would be worse than
    # one that fails (INV-4, INV-5, HO §131).
    it "refuses to display a payload that fails its integrity check" do
      target = observation
      allow_any_instance_of(RawEnvelope).to receive(:payload)
        .and_raise(Storage::RawPayloadStore::IntegrityError, "does not match its recorded hash")

      get admin_provenance_path(target)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("INTEGRITY CHECK FAILED")
      expect(response.body).not_to include("&quot;systolic&quot;:142")
    end
  end

  describe "auditing (HO §92, §157)" do
    before { sign_in staff_user }

    it "records that evidence was viewed" do
      target = observation

      expect { get admin_provenance_path(target) }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:occurred_at).last
      expect(event.event_type).to eq("admin.provenance.viewed")
      expect(event.metadata["observation_id"]).to eq(target.id)
      expect(event.metadata["integrity"]).to eq("verified")
    end
  end
end
