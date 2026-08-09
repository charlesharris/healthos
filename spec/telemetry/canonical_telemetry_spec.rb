# frozen_string_literal: true

require "rails_helper"

# Epic 001-07. HO §16–21, §28. STAT-002, STAT-005, STAT-010; INV-2.
RSpec.describe "Canonical telemetry", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "America/New_York") }
  let!(:source) do
    Source.create!(organization: organization, key: "synthetic-bp",
                   source_type: "synthetic", display_name: "Synthetic BP")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: source, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_json", adapter_version: "1"
    )
  end

  def build_observation(**overrides)
    {
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r1",
      semantic_key: "health.vital.blood_pressure.systolic", semantic_version: 1,
      value_numeric: 142, unit: "mmHg",
      observed_at: Time.utc(2026, 3, 15, 14, 0), normalized_at: Time.current,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    }.merge(overrides)
  end

  # HO §16: "use a CHECK constraint so value representation is internally
  # valid". This is what makes STAT-002 structural: there is no way to record
  # an absent measurement carrying a zero.
  describe "value representation CHECK (HO §16, STAT-002)" do
    it "accepts an observed measurement with exactly one value representation" do
      expect { Observation.create!(**build_observation) }.not_to raise_error
    end

    it "rejects an observed measurement with no value at all" do
      expect {
        Observation.create!(**build_observation(value_numeric: nil, unit: nil))
      }.to raise_error(ActiveRecord::StatementInvalid, /observations_value_representation_check/)
    end

    it "rejects an observed measurement carrying two representations at once" do
      expect {
        Observation.create!(**build_observation(value_text: "one forty two"))
      }.to raise_error(ActiveRecord::StatementInvalid, /observations_value_representation_check/)
    end

    # The heart of STAT-002. A gap in the record cannot be given a number, so
    # zero-imputation is impossible at the storage layer rather than merely
    # discouraged in review.
    it "refuses to attach a value to a missing measurement" do
      expect {
        Observation.create!(**build_observation(quality_state: "expected_but_missing"))
      }.to raise_error(ActiveRecord::StatementInvalid, /observations_value_representation_check/)
    end

    it "refuses to attach a ZERO to a missing measurement" do
      expect {
        Observation.create!(**build_observation(quality_state: "device_not_reporting", value_numeric: 0))
      }.to raise_error(ActiveRecord::StatementInvalid, /observations_value_representation_check/)
    end

    it "accepts a missing measurement carrying no value" do
      record = Observation.create!(
        **build_observation(quality_state: "device_not_reporting", value_numeric: nil, unit: nil)
      )

      expect(record).to be_missing
      expect(record.value).to be_nil
    end

    it "rejects a numeric value with no unit" do
      expect {
        Observation.create!(**build_observation(unit: nil))
      }.to raise_error(ActiveRecord::StatementInvalid, /numeric_requires_unit/)
    end
  end

  describe "missingness taxonomy (HO §28, STAT-010)" do
    it "distinguishes ten states rather than a boolean" do
      expect(Observation::QUALITY_STATES.size).to eq(10)
      expect(Observation::QUALITY_STATES).to include(
        "device_not_reporting", "manual_entry_absent", "late_not_yet_arrived", "not_expected"
      )
    end

    # The distinction that matters: a device that stopped reporting is an
    # instrumentation finding; a person who stopped entering readings is a
    # behavioural one (STAT-003). Collapsing them loses the difference.
    it "keeps device and manual absence distinguishable" do
      device_gap = Observation.create!(**build_observation(
        quality_state: "device_not_reporting", value_numeric: nil, unit: nil, observed_at: 1.day.ago
      ))
      manual_gap = Observation.create!(**build_observation(
        quality_state: "manual_entry_absent", value_numeric: nil, unit: nil, observed_at: 2.days.ago
      ))

      expect(device_gap.quality_state).not_to eq(manual_gap.quality_state)
      expect(Observation.missing).to include(device_gap, manual_gap)
      expect(Observation.observed).to be_empty
    end

    it "treats not_expected as absent but not as a gap" do
      # not_expected is not a shortfall — a lab that is not due today is not
      # missing (SC §13).
      expect(Observation::EXPECTED_BUT_ABSENT_STATES).not_to include("not_expected")
      expect(Observation::MISSING_STATES).to include("not_expected")
    end

    it "rejects a quality state outside the taxonomy" do
      expect {
        Observation.create!(**build_observation(quality_state: "missing"))
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects it at the database too, when validation is skipped" do
      # No value, so it is the quality_state CHECK that refuses this and not
      # the value-representation one.
      # public_id set explicitly: save!(validate: false) skips the
      # before_validation that would otherwise assign it, and a NOT NULL
      # violation would fire before the CHECK being tested.
      record = Observation.new(**build_observation(
        quality_state: "missing", value_numeric: nil, unit: nil,
        public_id: "obs_#{SecureRandom.alphanumeric(20).downcase}"
      ))

      expect { record.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /quality_state_check/)
    end
  end

  describe "INV-2 append-only" do
    it "refuses to mutate a persisted observation" do
      record = Observation.create!(**build_observation)

      expect { record.update!(value_numeric: 200) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    # Separate examples: a failed statement aborts the surrounding
    # transaction, so a second one in the same example reports
    # InFailedSqlTransaction rather than the permission error being asserted.
    it "refuses UPDATE at the database" do
      record = Observation.create!(**build_observation)

      expect {
        Observation.connection.execute("UPDATE observations SET value_numeric = 200 WHERE id = '#{record.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end

    it "refuses DELETE at the database" do
      record = Observation.create!(**build_observation)

      expect {
        Observation.connection.execute("DELETE FROM observations WHERE id = '#{record.id}'")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
    end
  end

  describe "normalization idempotency (§96)" do
    it "rejects a duplicate row for the same envelope, key, version and time" do
      Observation.create!(**build_observation)

      expect { Observation.create!(**build_observation) }
        .to raise_error(ActiveRecord::RecordNotUnique, /normalization_identity/)
    end

    # HO §155: reprocessing creates NEW artifacts rather than rewriting old
    # ones, so a new normalizer version must be able to coexist with the old.
    it "allows the same input to normalize again under a new normalizer version" do
      Observation.create!(**build_observation)

      expect { Observation.create!(**build_observation(normalizer_version: 2)) }
        .not_to raise_error
      expect(Observation.count).to eq(2)
    end
  end

  describe "HO §21 provenance" do
    it "exposes every element §21 requires" do
      record = Observation.create!(**build_observation(
        recording_method: "device_automatic", measurement_protocol: "seated_rest_5min"
      ))

      expect(record.provenance).to include(
        raw_envelope_id: envelope.id,
        source_id: source.id,
        recording_method: "device_automatic",
        measurement_protocol: "seated_rest_5min",
        normalizer: "synthetic_bp_json@v1",
        semantic: "health.vital.blood_pressure.systolic@v1"
      )
    end

    it "resolves to its semantic definition" do
      record = Observation.create!(**build_observation)

      expect(record.semantic_definition.unit).to eq("mmHg")
      expect(record.semantic_definition).to be_phi
    end
  end

  describe "observation groups (HO §17, STAT-005)" do
    # Three observations from one cuff inflation are ONE analytical unit, not
    # three. The group is what records that, and without it n would be
    # inflated threefold.
    it "binds a joint measurement into one unit" do
      group = ObservationGroup.create!(
        organization: organization, subject: subject_record, source: source,
        raw_envelope: envelope, semantic_key: "health.vital.blood_pressure",
        semantic_version: 1, observed_at: Time.utc(2026, 3, 15, 14, 0)
      )

      %w[systolic diastolic].each_with_index do |part, i|
        Observation.create!(**build_observation(
          observation_group: group,
          semantic_key: "health.vital.blood_pressure.#{part}",
          value_numeric: 142 - (i * 54)
        ))
      end
      Observation.create!(**build_observation(
        observation_group: group, semantic_key: "health.vital.pulse",
        value_numeric: 68, unit: "bpm"
      ))

      expect(group.observations.count).to eq(3)
      expect(group.observations.map(&:observed_at).uniq.size).to eq(1)
    end
  end

  describe "numeric precision" do
    # decimal, not float. A BP of 142 must never come back as
    # 141.99999999999997; binary floating point has no place in clinical
    # evidence.
    it "stores numerics exactly" do
      record = Observation.create!(**build_observation(value_numeric: BigDecimal("142.7")))

      expect(record.reload.value_numeric).to eq(BigDecimal("142.7"))
      expect(record.value_numeric).to be_a(BigDecimal)
    end
  end

  describe "device transitions (HO §20, STAT-008/009)" do
    it "answers which devices were recording across a window" do
      cuff = Device.create!(organization: organization, source: source, subject: subject_record,
                            external_id: "cuff-1", device_type: "bp_cuff",
                            active_from: Time.utc(2026, 1, 1), active_to: Time.utc(2026, 3, 10))
      manual = Device.create!(organization: organization, source: source, subject: subject_record,
                              external_id: "manual-1", device_type: "manual",
                              active_from: Time.utc(2026, 3, 8))

      overlapping = Device.active_during(Time.utc(2026, 3, 1), Time.utc(2026, 3, 20))

      # Two devices across one window is exactly the source-mix change that
      # caps biological evidence at WEAK (STAT-008).
      expect(overlapping).to contain_exactly(cuff, manual)
      expect(Device.active_at(Time.utc(2026, 3, 20))).to contain_exactly(manual)
    end
  end
end
