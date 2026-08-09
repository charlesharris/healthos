# frozen_string_literal: true

require "rails_helper"

# Epic 003-02, 003-04, 003-05, 003-09. HO §51-54, §80; INV-3, INV-9, INV-13;
# STAT-002, STAT-003, STAT-031.
RSpec.describe "Context materialization", type: :model do
  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }
  let!(:cuff) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "Cuff")
  end
  let!(:manual) do
    Source.create!(organization: organization, key: "manual", source_type: "manual",
                   display_name: "Manual")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: cuff, source_record_id: "r",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:as_of) { Time.utc(2026, 3, 22, 0, 0) }
  let(:window) { [ as_of - 7.days, as_of ] }

  def observe(days_ago:, value: 130, key: "health.vital.blood_pressure.systolic",
              source: cuff, method: "device_automatic", quality_state: "observed")
    Observation.create!(
      organization: organization, subject: subject_record, source: source,
      raw_envelope: envelope, source_record_id: "r-#{days_ago}-#{key}-#{source.key}",
      semantic_key: key, semantic_version: 1,
      value_numeric: quality_state == "observed" ? value : nil,
      unit: quality_state == "observed" ? (key.include?("pulse") ? "bpm" : "mmHg") : nil,
      observed_at: as_of - days_ago.days + 12.hours, normalized_at: Time.current,
      quality_state: quality_state, recording_method: method,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def materialize
    Analysis::MaterializeContext.call(subject: subject_record, window: window, as_of: as_of)
  end

  describe "HO §51 definition identity (INV-9)" do
    it "stamps key, version and digest on the Context" do
      (1..5).each { |d| observe(days_ago: d) }
      context = materialize.context

      expect(context.definition).to eq("blood_pressure_change@v1")
      expect(context.definition_digest)
        .to eq(Hypertension::BloodPressureChangeContext.digest)
    end

    it "changes the digest when a parameter changes" do
      variant = Class.new(Hypertension::BloodPressureChangeContext) do
        def self.parameters = super.merge(extra: true)
      end

      expect(variant.digest).not_to eq(Hypertension::BloodPressureChangeContext.digest)
    end
  end

  describe "HO §80 reproducibility tuple" do
    it "records the versions the artifact was computed under" do
      (1..5).each { |d| observe(days_ago: d) }
      tuple = materialize.context.version_tuple

      expect(tuple["definition"]).to include("key" => "blood_pressure_change", "version" => 1)
      expect(tuple["semantic_registry_digest"]).to match(/\A[0-9a-f]{64}\z/)
      # A threshold change becomes visible in the artifact, not only in git.
      expect(tuple["statistical_config_digest"])
        .to eq(Analysis::StatisticalConfig.instance.digest)
    end
  end

  describe "STAT-003 measurement behaviour is materialized alongside biology" do
    # A Context emitting only blood pressure would make STAT-007's
    # instrumentation-before-biology ordering impossible: the comparison
    # engine would have nothing to order against.
    it "emits measurement dimensions next to biological ones" do
      (1..5).each { |d| observe(days_ago: d) }
      keys = materialize.context.context_values.pluck(:dimension_key)

      expect(keys).to include("health.vital.blood_pressure.systolic")
      expect(keys).to include("health.measurement.completeness")
      expect(keys).to include("health.measurement.source_changed")
    end

    it "reports a source change as a dimension, with the mix" do
      (1..3).each { |d| observe(days_ago: d, source: cuff) }
      (4..5).each { |d| observe(days_ago: d, source: manual, method: "manual_entry") }

      value = materialize.context.value_for("health.measurement.source_changed")

      expect(value.value_boolean).to be(true)
      expect(value.details["source_count"]).to eq(2)
    end

    # A knowable zero and an unknowable ratio are different claims, and a gate
    # must not confuse them. Blood pressure declares a daily expectation
    # model, so a subject who measured nothing has a REAL 0% — they were
    # expected to measure and did not. That is `observed`, not `unknown`.
    it "reports a genuine zero as observed, not unknown" do
      empty = Subject.create!(organization: organization, timezone: "UTC")
      context = Analysis::MaterializeContext.call(
        subject: empty, window: window, as_of: as_of
      ).context

      completeness = context.value_for("health.measurement.completeness")

      expect(completeness.quality_state).to eq("observed")
      expect(completeness.value_numeric).to eq(0)
      expect(completeness.details["expected_total"]).to eq(7)
    end

    # The unknown path belongs to dimensions with no declared expectation
    # model — proven directly against Completeness in
    # spec/measurement/expectation_and_completeness_spec.rb. Asserted here
    # only that the Context propagates it rather than flattening it to zero.
    it "propagates an indeterminate completeness as unknown" do
      allow(Measurement::Completeness).to receive(:call).and_return(
        Measurement::Completeness::Result.new(
          ratio: nil, usable: 0, expected_total: 0, observed: 0,
          missing_by_state: {}, indeterminate: true, reason: "no_expectation_model"
        )
      )

      context = materialize.context
      completeness = context.value_for("health.measurement.completeness")

      expect(completeness.quality_state).to eq("unknown")
      expect(completeness.value_numeric).to be_nil
      expect(completeness.details["reason"]).to eq("no_expectation_model")
    end
  end

  describe "STAT-002 at the analytical layer" do
    # Emitted rather than omitted, so a Comparison can tell "we looked and
    # found nothing usable" from "we never looked".
    it "emits a dimension with no value when nothing is usable" do
      observe(days_ago: 1, quality_state: "device_not_reporting")

      value = materialize.context.value_for("health.vital.blood_pressure.systolic")

      expect(value.quality_state).to eq("expected_but_missing")
      expect(value.value_numeric).to be_nil
      expect(value.value).to be_nil
    end

    it "refuses at the database to give a non-observed dimension a value" do
      (1..5).each { |d| observe(days_ago: d) }
      context = materialize.context

      record = Analysis::ContextValue.new(
        organization_id: organization.id, context: context,
        dimension_key: "x", dimension_version: 1,
        value_numeric: 0, quality_state: "expected_but_missing"
      )

      expect { record.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /value_representation_check/)
    end
  end

  describe "SC §49–50 difference families (STAT-031)" do
    # Families come from the registry so a dimension's family is declared once.
    # A definition restating them would let the two drift, and STAT-033's
    # suppression would then reason about families that no longer match.
    it "carries families read from the semantic registry" do
      (1..5).each { |d| observe(days_ago: d) }
      value = materialize.context.value_for("health.vital.blood_pressure.systolic")

      expect(value.semantic_family)
        .to eq(Definitions::Registry.find("health.vital.blood_pressure.systolic").semantic_family)
    end

    it "puts systolic and diastolic in the same family, pulse in another" do
      (1..5).each do |d|
        observe(days_ago: d)
        observe(days_ago: d, key: "health.vital.blood_pressure.diastolic", value: 85)
        observe(days_ago: d, key: "health.vital.pulse", value: 70)
      end

      context = materialize.context
      systolic = context.value_for("health.vital.blood_pressure.systolic")
      diastolic = context.value_for("health.vital.blood_pressure.diastolic")
      pulse = context.value_for("health.vital.pulse")

      expect(systolic).to be_same_family_as(diastolic)
      expect(systolic).not_to be_same_family_as(pulse)
    end

    it "marks dispersion as a distinct derivation family" do
      (1..5).each { |d| observe(days_ago: d, value: 120 + d) }

      dispersion = materialize.context.value_for("health.vital.blood_pressure.systolic.dispersion")
      expect(dispersion.derivation_family).to eq("dispersion")
    end
  end

  describe "HO §26 idempotency and INV-3 lineage" do
    it "returns the existing Context when inputs are unchanged" do
      (1..5).each { |d| observe(days_ago: d) }

      first = materialize
      second = materialize

      expect(first).to be_created
      expect(second).not_to be_created
      expect(second.context).to eq(first.context)
      expect(Analysis::Context.count).to eq(1)
    end

    it "resolves lineage to the exact observations" do
      readings = (1..5).map { |d| observe(days_ago: d) }

      context = materialize.context

      expect(context.inputs).to match_array(readings)
      expect(context.input_evidence_set.purpose).to eq("context_inputs")
    end

    # HO §50: analytical artifacts are immutable snapshots.
    it "refuses to mutate a materialized Context or its values" do
      (1..5).each { |d| observe(days_ago: d) }
      context = materialize.context

      expect { context.update!(status: "failed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { context.context_values.first.update!(value_numeric: 1) }
        .to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "the definition computes but does not judge" do
    # A gate hidden in a materializer would be a governed threshold nobody
    # reviews. The Context describes; the Comparison decides.
    it "encodes no evidence level or gate" do
      code = Rails.root.join("app/domain_packs/hypertension/contexts/blood_pressure_change_context.rb")
        .read.lines.reject { |l| l.strip.start_with?("#") }.join

      expect(code).not_to match(/evidence_level|WEAK|MODERATE|STRONG|suppress/i)
    end
  end
end
