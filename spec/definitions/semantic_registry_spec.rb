# frozen_string_literal: true

require "rails_helper"

# Epic 001-06. HO §23 (semantic registry), §25 (definition identity),
# §125 (digest CI check). INV-7: semantic definitions are versioned.
RSpec.describe "Semantic registry", type: :model do
  let(:registry) { Definitions::Registry.instance }

  describe "HO §23 registry" do
    it "loads platform-core and domain-pack definitions" do
      expect(registry.keys).to include(
        "health.vital.blood_pressure.systolic",
        "health.vital.blood_pressure.diastolic",
        "health.vital.pulse",
        "health.measurement.frequency",
        "health.measurement.completeness"
      )
    end

    it "reserves the health.measurement.* keys the epic requires" do
      measurement_keys = registry.keys.select { |k| k.start_with?("health.measurement.") }

      expect(measurement_keys).to include(
        "health.measurement.frequency",
        "health.measurement.completeness",
        "health.measurement.source_changed"
      )
    end

    it "fetches a specific version, so historical artifacts stay resolvable" do
      definition = registry.fetch("health.vital.blood_pressure.systolic", version: 1)

      expect(definition.version).to eq(1)
      expect(definition.unit).to eq("mmHg")
    end

    it "raises for an unknown key rather than returning nil" do
      expect { registry.fetch("health.vital.nonexistent") }
        .to raise_error(Definitions::Registry::UnknownDefinition)
    end

    it "raises for a version that does not exist" do
      expect { registry.fetch("health.vital.pulse", version: 99) }
        .to raise_error(Definitions::Registry::UnknownDefinition, /no version 99/)
    end
  end

  describe "INV-35 domain neutrality" do
    # CLAUDE.md's test: "would this still make sense for post-op recovery or
    # oncology?" Blood pressure would not, so it lives in the domain pack.
    it "keeps disease-specific semantics out of platform core" do
      core_keys = YAML.safe_load_file(Rails.root.join("config/semantics/core.yml"))
        .fetch("definitions").map { |d| d["key"] }

      expect(core_keys).to all(start_with("health.measurement."))
      expect(core_keys).not_to include(a_string_matching(/blood_pressure|pulse/))
    end
  end

  describe "SC §49–50 difference families" do
    # STAT-033: correlated same-family derivatives must never count as
    # independent confirmation. The family metadata that makes that possible
    # is carried on the definition, so it can never require a schema change.
    it "puts systolic and diastolic in the same semantic family" do
      systolic = registry.fetch("health.vital.blood_pressure.systolic")
      diastolic = registry.fetch("health.vital.blood_pressure.diastolic")

      expect(systolic.semantic_family).to eq(diastolic.semantic_family)
    end

    # STAT-034: genuinely independent support may raise evidence one level.
    it "puts pulse in a different semantic family from blood pressure" do
      pulse = registry.fetch("health.vital.pulse")
      systolic = registry.fetch("health.vital.blood_pressure.systolic")

      expect(pulse.semantic_family).not_to eq(systolic.semantic_family)
    end

    it "shares a derivation family between a summary and its inputs" do
      summary = registry.fetch("health.vital.blood_pressure.daily_summary")
      systolic = registry.fetch("health.vital.blood_pressure.systolic")

      expect(summary.derivation_family).to eq(systolic.derivation_family)
    end
  end

  describe "privacy classification (HO §23, PD §57)" do
    it "classifies every definition" do
      expect(registry.all.map(&:privacy_class).uniq)
        .to all(be_in(Definitions::SemanticDefinition::PRIVACY_CLASSES))
    end

    it "marks vitals as PHI and measurement behaviour as operational" do
      expect(registry.fetch("health.vital.blood_pressure.systolic")).to be_phi
      expect(registry.fetch("health.measurement.completeness")).not_to be_phi
    end
  end

  describe "definition validation" do
    it "rejects a numeric definition with no unit" do
      expect {
        Definitions::SemanticDefinition.new(
          key: "x", version: 1, kind: "vital", value_type: "numeric", privacy_class: "phi"
        )
      }.to raise_error(ArgumentError, /must declare a unit/)
    end

    it "rejects an unknown privacy class" do
      expect {
        Definitions::SemanticDefinition.new(
          key: "x", version: 1, kind: "vital", value_type: "boolean", privacy_class: "whatever"
        )
      }.to raise_error(ArgumentError, /privacy_class/)
    end

    it "is immutable once constructed (HO §23)" do
      definition = registry.fetch("health.vital.pulse")

      expect(definition).to be_frozen
    end
  end

  describe "HO §25 definition identity" do
    it "exposes key, version and digest" do
      identity = registry.fetch("health.vital.pulse").identity

      expect(identity.keys).to contain_exactly(:key, :version, :digest)
      expect(identity[:digest]).to match(/\A[0-9a-f]{64}\z/)
    end

    it "is stable across reloads" do
      before = registry.fetch("health.vital.pulse").digest
      Definitions::Registry.reload!

      expect(Definitions::Registry.instance.fetch("health.vital.pulse").digest).to eq(before)
    end

    # The digest is computed over normalized content, not raw text. Without
    # this, reindenting a YAML file would demand a version bump — which trains
    # people to bump reflexively and destroys the signal the gate depends on.
    it "ignores formatting and key order" do
      a = Definitions::DefinitionDigest.compute(
        key: "x", version: 1, unit: "mmHg", nested: { b: 2, a: 1 }
      )
      b = Definitions::DefinitionDigest.compute(
        "version" => 1, "key" => "x", "nested" => { "a" => 1, "b" => 2 }, "unit" => "mmHg"
      )

      expect(a).to eq(b)
    end

    it "changes when content genuinely changes" do
      a = Definitions::DefinitionDigest.compute(key: "x", threshold: 10)
      b = Definitions::DefinitionDigest.compute(key: "x", threshold: 11)

      expect(a).not_to eq(b)
    end
  end

  # The epic's named spec: "changing a definition without version bump fails
  # verify". This is the gate that protects INV-6..12 — without it a threshold
  # can be edited and every historical artifact silently reinterpreted.
  describe "HO §125 digest verification" do
    let(:lockfile) { Rails.root.join("tmp/spec_definition_digests.yml") }
    let(:verifier) { Definitions::Verifier.new(lockfile: lockfile) }

    after { FileUtils.rm_f(lockfile) }

    it "passes when the lockfile matches the registry" do
      verifier.write_lockfile!

      expect(verifier.call).to be_ok
    end

    it "FAILS when a definition's content changes without a version bump" do
      verifier.write_lockfile!

      recorded = YAML.safe_load_file(lockfile)
      key = "health.vital.blood_pressure.systolic@v1"
      recorded["digests"][key] = "0" * 64 # simulate the definition having changed
      File.write(lockfile, recorded.to_yaml)

      result = verifier.call

      expect(result).not_to be_ok
      expect(result).to be_drift
      expect(result.changed.map { |c| c[:key] }).to include(key)
    end

    it "FAILS when a definition is removed" do
      verifier.write_lockfile!

      recorded = YAML.safe_load_file(lockfile)
      recorded["digests"]["health.vital.retired_thing@v1"] = "a" * 64
      File.write(lockfile, recorded.to_yaml)

      result = verifier.call

      expect(result).not_to be_ok
      expect(result.removed).to include("health.vital.retired_thing@v1")
    end

    it "FAILS when a definition is added but the lockfile is not updated" do
      verifier.write_lockfile!

      recorded = YAML.safe_load_file(lockfile)
      recorded["digests"].delete("health.vital.pulse@v1")
      File.write(lockfile, recorded.to_yaml)

      result = verifier.call

      expect(result).not_to be_ok
      expect(result.added).to include("health.vital.pulse@v1")
      # Distinguished from drift: adding is legitimate, it just has to be
      # committed alongside.
      expect(result).not_to be_drift
    end
  end

  describe "the committed lockfile" do
    it "is current" do
      result = Definitions::Verifier.call

      expect(result).to be_ok,
        "Run `bin/definitions update` and commit config/definition_digests.yml. " \
        "changed=#{result.changed.map { |c| c[:key] }} " \
        "removed=#{result.removed} added=#{result.added}"
    end
  end
end
