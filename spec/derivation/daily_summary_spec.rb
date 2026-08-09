# frozen_string_literal: true

require "rails_helper"

# Epic 001-09. HO §22 (evidence sets), §26 (derived signals), §96
# (idempotency); INV-3, INV-8; STAT-002, STAT-004/005, STAT-021.
#
# The epic names one spec: "recompute with same inputs → same identity, no
# duplicate; lineage resolves to exact input observations".
RSpec.describe "Daily derived summary", type: :model do
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
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:systolic_key) { "health.vital.blood_pressure.systolic" }

  def observe(value, at:, quality_state: "observed")
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r1",
      semantic_key: systolic_key, semantic_version: 1,
      value_numeric: quality_state == "observed" ? value : nil,
      unit: quality_state == "observed" ? "mmHg" : nil,
      observed_at: at, normalized_at: Time.current,
      quality_state: quality_state,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def compute(date: Date.new(2026, 3, 15))
    Derivation::ComputeDailySummary.call(
      subject: subject_record, semantic_key: systolic_key, date: date
    )
  end

  # 14:00 and 18:00 New York on 2026-03-15.
  let(:morning) { Time.utc(2026, 3, 15, 18, 0) }
  let(:evening) { Time.utc(2026, 3, 15, 22, 0) }

  describe "computation" do
    it "summarizes a day's readings with the median" do
      observe(140, at: morning)
      observe(150, at: evening)
      observe(200, at: evening + 1.minute) # outlier

      signal = compute.derived_signal

      # Median 150, not mean 163.3. SC §29 prefers robust summaries: one
      # mis-cuffed reading must not look like a genuine shift.
      expect(signal.value_numeric).to eq(150)
      expect(signal.unit).to eq("mmHg")
      expect(signal).to be_computed
    end

    it "averages the middle two on an even count, exactly" do
      observe(140, at: morning)
      observe(150, at: evening)

      expect(compute.derived_signal.value_numeric).to eq(BigDecimal("145"))
    end

    it "stamps the algorithm key, version and digest (INV-8)" do
      observe(140, at: morning)
      signal = compute.derived_signal

      expect(signal.algorithm).to eq("daily_blood_pressure_summary@v1")
      expect(signal.algorithm_digest).to eq(Hypertension::DailyBloodPressureSummary.digest)
      expect(signal.algorithm_digest).to match(/\A[0-9a-f]{64}\z/)
    end

    # The digest exists to catch a behaviour change made without a version
    # bump — the same protection HO §25 gives semantic definitions.
    it "changes the digest when a parameter changes" do
      variant = Class.new(Hypertension::DailyBloodPressureSummary) do
        def self.parameters = super.merge(aggregation: "mean")
      end

      expect(variant.digest).not_to eq(Hypertension::DailyBloodPressureSummary.digest)
    end
  end

  describe "STAT-002 missing is never imputed" do
    it "counts a missing reading in the denominator but not the value" do
      observe(140, at: morning)
      observe(nil, at: evening, quality_state: "device_not_reporting")

      signal = compute.derived_signal

      # The median is of the one usable reading. The gap is visible in the
      # denominator, never filled with a zero or an average.
      expect(signal.value_numeric).to eq(140)
      expect(signal.denominator).to eq(usable: 1, raw: 2)
    end

    it "produces insufficient_input rather than a value when nothing is usable" do
      observe(nil, at: morning, quality_state: "device_not_reporting")
      observe(nil, at: evening, quality_state: "manual_entry_absent")

      signal = compute.derived_signal

      expect(signal.status).to eq("insufficient_input")
      expect(signal.value_numeric).to be_nil
      expect(signal.denominator).to eq(usable: 0, raw: 2)
    end

    # A day with no usable readings must not be recordable as a value of zero.
    it "refuses at the database to give a non-computed signal a value" do
      record = DerivedSignal.new(
        organization: organization, subject: subject_record,
        semantic_key: "health.vital.blood_pressure.daily_summary", semantic_version: 1,
        window_started_at: morning, window_ended_at: evening,
        value_numeric: 0, status: "insufficient_input",
        algorithm_key: "x", algorithm_version: 1, algorithm_digest: "d",
        computed_at: Time.current, as_of: evening
      )

      expect { record.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /value_representation_check/)
    end
  end

  describe "STAT-021 persisted denominators" do
    it "persists usable and raw counts separately" do
      observe(140, at: morning)
      observe(150, at: evening)
      observe(nil, at: evening + 1.minute, quality_state: "invalid_measurement")

      signal = compute.derived_signal

      # STAT-004/005: raw count is not n. Both are stored so the distinction
      # survives into the artifact rather than being recomputed later, when it
      # would answer a different question.
      expect(signal.usable_input_count).to eq(2)
      expect(signal.raw_input_count).to eq(3)
    end
  end

  # The epic's named spec.
  describe "HO §96 idempotency and INV-3 lineage" do
    it "recomputes to the same row rather than duplicating" do
      observe(140, at: morning)

      first = compute
      second = compute

      expect(first).to be_created
      expect(second).not_to be_created
      expect(second.derived_signal).to eq(first.derived_signal)
      expect(DerivedSignal.count).to eq(1)
    end

    it "resolves lineage to the exact input observations" do
      a = observe(140, at: morning)
      b = observe(150, at: evening)

      signal = compute.derived_signal

      expect(signal.inputs).to contain_exactly(a, b)
      expect(signal.evidence_set.purpose).to eq("derived_signal_inputs")
    end

    it "excludes unusable readings from lineage while counting them" do
      usable = observe(140, at: morning)
      observe(nil, at: evening, quality_state: "device_not_reporting")

      signal = compute.derived_signal

      # Lineage records what produced the VALUE; the denominator records what
      # was considered. Conflating them would misrepresent the evidence.
      expect(signal.inputs).to contain_exactly(usable)
      expect(signal.raw_input_count).to eq(2)
    end

    it "fingerprints identical input sets identically" do
      a = observe(140, at: morning)
      b = observe(150, at: evening)

      expect(EvidenceSet.fingerprint_for([ a, b ]))
        .to eq(EvidenceSet.fingerprint_for([ b, a ]))
      expect(EvidenceSet.fingerprint_for([ a ]))
        .not_to eq(EvidenceSet.fingerprint_for([ a, b ]))
    end

    it "allows a new algorithm version to compute alongside the old" do
      observe(140, at: morning)
      compute

      v2 = Class.new(Hypertension::DailyBloodPressureSummary) do
        def self.version = 2
      end
      result = Derivation::ComputeDailySummary.call(
        subject: subject_record, semantic_key: systolic_key,
        date: Date.new(2026, 3, 15), algorithm: v2
      )

      # HO §26: never overwrite a signal a pinned Investigation may reference.
      expect(result).to be_created
      expect(DerivedSignal.count).to eq(2)
    end
  end

  describe "subject-local windows (HO §121)" do
    it "assigns a late-evening reading to the subject's local day" do
      # 2026-03-16 01:00 UTC is 2026-03-15 21:00 in New York.
      observe(140, at: Time.utc(2026, 3, 16, 1, 0))

      signal = compute(date: Date.new(2026, 3, 15)).derived_signal

      expect(signal).to be_computed
      expect(signal.value_numeric).to eq(140)
    end

    it "excludes a reading that falls in the next local day" do
      # 2026-03-16 05:00 UTC is 2026-03-16 01:00 in New York.
      observe(140, at: Time.utc(2026, 3, 16, 5, 0))

      expect(compute(date: Date.new(2026, 3, 15)).derived_signal.status)
        .to eq("insufficient_input")
    end
  end

  describe "INV-3 append-only lineage" do
    it "refuses to mutate a derived signal or its evidence" do
      observe(140, at: morning)
      signal = compute.derived_signal

      expect { signal.update!(value_numeric: 200) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { signal.evidence_set.update!(purpose: "context_inputs") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "only admits canonical record types as evidence" do
      item = EvidenceItem.new(
        evidence_set: EvidenceSet.record!(
          organization: organization, purpose: "derived_signal_inputs",
          as_of: Time.current, records: []
        ),
        organization: organization, record_type: "User", record_id: SecureRandom.uuid
      )

      expect(item).not_to be_valid
    end
  end
end
