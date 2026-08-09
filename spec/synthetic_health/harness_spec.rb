# frozen_string_literal: true

require_relative "../support/synthetic_health/all"

# Specs for the simulation harness itself (epic 003-01, HO §100).
#
# The harness is the acceptance instrument for the entire statistical engine,
# so it needs its own acceptance tests. If the generator is wrong or
# irreproducible, every downstream statistical spec is measuring nothing.
#
# Deliberately Rails-free: this file requires the harness directly and never
# touches a database. That is a property worth protecting — the harness has to
# stay portable to v2, and a suite that cannot run without a schema is a
# suite that has quietly acquired a dependency.
RSpec.describe "SyntheticHealth harness" do
  include SyntheticHealth

  let(:systolic) { SyntheticHealth::Dimensions::SYSTOLIC.semantic_key }

  # ------------------------------------------------------------------
  # Determinism (HO §100: "Deterministic seeds")
  # ------------------------------------------------------------------
  describe "determinism" do
    it "produces byte-identical output for the same seed, for every family" do
      SyntheticHealth::Scenarios::FAMILIES.each do |family|
        first = SyntheticHealth::Scenarios.build(family, seed: 4242)
        second = SyntheticHealth::Scenarios.build(family, seed: 4242)

        expect(second.digest).to eq(first.digest), "#{family} digest is not reproducible"
        expect(second.readings).to eq(first.readings), "#{family} readings are not reproducible"
        expect(second.latent_series).to eq(first.latent_series), "#{family} latent series is not reproducible"
      end
    end

    it "differs for different seeds, for every family" do
      SyntheticHealth::Scenarios::FAMILIES.each do |family|
        one = SyntheticHealth::Scenarios.build(family, seed: 1)
        two = SyntheticHealth::Scenarios.build(family, seed: 2)

        expect(two.digest).not_to eq(one.digest), "#{family} ignores its seed"
      end
    end

    it "is stable across repeated reads of the same scenario" do
      scenario = SyntheticHealth::Scenarios.build(:missingness_artifact, seed: 99)

      expect(scenario.readings).to equal(scenario.readings)
      expect(scenario.digest).to eq(scenario.digest)
    end

    it "requires an explicit integer seed" do
      expect { SyntheticHealth::TrajectoryScenario.null(seed: "4242") }
        .to raise_error(ArgumentError, /seed must be an Integer/)
    end

    # String#hash is salted per process. Deriving stream seeds from it would
    # make output reproducible within one run and different in the next — the
    # worst possible failure mode, because it looks deterministic locally and
    # breaks in CI.
    it "derives stream seeds from a process-stable hash, not String#hash" do
      expect(SyntheticHealth::SeedStreams.derive(1, "values")).to eq(10_271_983_299_791_473_432)
      expect(SyntheticHealth::SeedStreams.derive(4242, "health.vital.pulse|white_noise"))
        .to eq(13_390_332_444_787_784_296)
    end

    it "never draws from the global RNG" do
      Kernel.srand(20_260_808)
      control = Array.new(5) { Kernel.rand }

      Kernel.srand(20_260_808)
      SyntheticHealth::Scenarios.all(seed: 7).each(&:readings)
      after_generation = Array.new(5) { Kernel.rand }

      expect(after_generation).to eq(control)
    end

    it "generates measurement values as BigDecimal, never Float" do
      SyntheticHealth::Scenarios.all(seed: 11).each do |scenario|
        values = scenario.readings.select(&:observed?).map(&:value)

        expect(values).to all(be_a(BigDecimal)), "#{scenario.family} emitted a non-BigDecimal value"
      end
    end
  end

  # ------------------------------------------------------------------
  # The null family (STAT-036: a negative result is a successful output)
  # ------------------------------------------------------------------
  describe "the null scenario" do
    subject(:scenario) { SyntheticHealth::Scenarios.build(:null, seed: 4242) }

    it "injects no effect at all" do
      expect(scenario.expected_effect).not_to be_present
      expect(scenario.expected_effect.kind).to eq(:none)
      expect(scenario.truth).not_to be_biological_effect_present
      expect(scenario.truth.effects.select(&:present?)).to be_empty
    end

    it "injects no confounder either" do
      expect(scenario.truth.confounders).to be_empty
    end

    it "contains only a level and noise in its value process" do
      components = scenario.truth.process.fetch(systolic).map { |component| component[:component] }

      expect(components).to eq(%w[level white_noise])
    end

    # A generator sanity check, NOT a statistical gate. It asserts that the
    # null family really is null — that no effect leaked in through a default
    # — by requiring the latent window-to-window movement to stay below the
    # per-reading noise scale. Whether an engine should report a difference of
    # this size is not asked here and is not the harness's business.
    it "moves less between windows than a single reading's noise, across many seeds" do
      noise = SyntheticHealth::Dimensions::SYSTOLIC.noise_scale_decimal

      (1..25).each do |seed|
        scenario = SyntheticHealth::Scenarios.build(:null, seed: seed)
        delta = scenario.truth.latent_median_delta(systolic)

        expect(delta.abs).to be < noise, "null seed #{seed} drifted by #{delta.to_s('F')}"
      end
    end

    it "still reports full denominators, because a null result is a result" do
      completeness = scenario.truth.completeness(systolic, :affected)

      expect(completeness[:expected]).to eq(28)
      expect(completeness[:usable]).to eq(28)
      expect(completeness[:ratio]).to eq("1.0")
    end
  end

  # ------------------------------------------------------------------
  # Level shift: ground truth matches what was generated
  # ------------------------------------------------------------------
  describe "the level-shift scenario" do
    subject(:scenario) { SyntheticHealth::Scenarios.build(:level_shift, seed: 4242) }

    let(:null) { SyntheticHealth::Scenarios.build(:null, seed: 4242) }

    it "describes the effect it injected" do
      effect = scenario.expected_effect

      expect(effect).to be_present
      expect(effect.kind).to eq(:level_shift)
      expect(effect.semantic_key).to eq(systolic)
      expect(effect.magnitude).to eq(BigDecimal(SyntheticHealth::Fixtures::LEVEL_SHIFT))
      expect(effect.unit).to eq("mmHg")
      expect(effect.direction).to eq(:increase)
      expect(effect.phase).to eq(:affected)
    end

    # The strongest available statement of ground truth, and the reason the
    # generator layers deterministic components over labelled random streams:
    # the shift scenario and the null scenario share identical noise, so the
    # difference between them is EXACTLY the injected magnitude — asserted
    # with no tolerance, at every index.
    it "differs from an identically-seeded null run by exactly the injected magnitude" do
      magnitude = scenario.expected_effect.magnitude
      injected = scenario.latent_series.fetch(systolic)
      baseline_process = null.latent_series.fetch(systolic)

      scenario.opportunities.each_with_index do |opportunity, index|
        expected = opportunity.phase == :affected ? magnitude : BigDecimal(0)

        expect(injected[index] - baseline_process[index]).to eq(expected),
          "index #{index} (#{opportunity.phase}) diverged from the declared effect"
      end
    end

    it "carries a caller-supplied magnitude through to ground truth" do
      custom = SyntheticHealth::TrajectoryScenario.level_shift(seed: 4242, magnitude: -17)

      expect(custom.expected_effect.magnitude).to eq(BigDecimal(-17))
      expect(custom.expected_effect.direction).to eq(:decrease)
      expect(custom.truth.latent_median_delta(systolic) - null.truth.latent_median_delta(systolic))
        .to eq(BigDecimal(-17))
    end

    it "reports the realized medians it generated, without judging them" do
      phases = scenario.truth.realized_for(systolic).fetch(:phases)

      expect(BigDecimal(phases.fetch(:affected).fetch(:median)))
        .to be > BigDecimal(phases.fetch(:baseline).fetch(:median))
      expect(scenario).not_to respond_to(:evidence_level)
      expect(scenario).not_to respond_to(:significant?)
    end

    it "declares a trend as a slope and a total, not as a step" do
      trend = SyntheticHealth::Scenarios.build(:trend, seed: 4242)

      expect(trend.expected_effect.kind).to eq(:trend)
      expect(trend.expected_effect.slope_per_day).to eq(BigDecimal("0.6"))
      # 0.6/day accumulated across a 14-day affected window.
      expect(trend.expected_effect.magnitude).to eq(BigDecimal("7.8"))
    end
  end

  # ------------------------------------------------------------------
  # Missingness (SC §12–17, STAT-002/010)
  # ------------------------------------------------------------------
  describe "missingness" do
    subject(:scenario) { SyntheticHealth::Scenarios.build(:missingness_artifact, seed: 4242) }

    it "emits one reading per opportunity per dimension in every family — never a silent gap" do
      SyntheticHealth::Scenarios.all(seed: 13).each do |candidate|
        expected = candidate.opportunities.size * candidate.dimensions.size

        expect(candidate.readings.size).to eq(expected), "#{candidate.family} dropped readings"
      end
    end

    it "gives every absent reading an explicit state from the ten-state taxonomy" do
      SyntheticHealth::Scenarios.all(seed: 13).each do |candidate|
        states = candidate.readings.map(&:quality_state).uniq

        expect(states - SyntheticHealth::QualityStates::ALL).to be_empty
      end
    end

    it "never stands a value in for absence, and never zero-imputes (STAT-002)" do
      SyntheticHealth::Scenarios.all(seed: 13).each do |candidate|
        absent = candidate.readings.reject(&:observed?)

        expect(absent.map(&:value).uniq).to eq([ nil ]).or be_empty
        expect(absent.map(&:unit).compact).to be_empty
        expect(candidate.readings.filter_map(&:value)).to all(be_nonzero)
      end
    end

    it "uses several distinct absence reasons rather than one collapsed state" do
      states = scenario.truth.realized_for(systolic).fetch(:phases).fetch(:affected).fetch(:missing_by_state)

      expect(states.keys.size).to be >= 2
      expect(states.keys - SyntheticHealth::QualityStates::MISSING).to be_empty
      expect(states.values.sum).to be_positive
    end

    it "reports completeness with its numerator and denominator, never a bare ratio (STAT-011/021)" do
      baseline = scenario.truth.completeness(systolic, :baseline)
      affected = scenario.truth.completeness(systolic, :affected)

      [ baseline, affected ].each do |completeness|
        expect(completeness.keys).to contain_exactly(:usable, :expected, :ratio)
        expect(completeness[:expected]).to be_positive
      end

      expect(affected[:usable]).to be < baseline[:usable]
    end

    # The point of the family: measurement behaviour changed and biology did
    # not. Because missingness is applied to an already-generated series, that
    # is provable rather than merely intended.
    it "leaves the underlying biology byte-identical to an unaffected run" do
      null = SyntheticHealth::Scenarios.build(:null, seed: 4242)

      expect(scenario.latent_series).to eq(null.latent_series)
      expect(scenario.truth).not_to be_biological_effect_present
      expect(scenario.truth.confounder_kinds).to include(:missingness_collapse)
    end

    it "distinguishes 'no measurement was due' from 'a measurement was missed'" do
      weekday = SyntheticHealth::TrajectoryScenario.null(
        seed: 7, schedule: SyntheticHealth::MeasurementSchedule.weekday_protocol
      )
      phases = weekday.truth.realized_for(systolic).fetch(:phases)
      baseline = phases.fetch(:baseline)

      expect(baseline.fetch(:not_expected)).to be_positive
      # not_expected is not a gap, so it stays out of the denominator (SC §12–14).
      expect(baseline.fetch(:expected_opportunities))
        .to eq(baseline.fetch(:raw_readings) - baseline.fetch(:not_expected))
      expect(baseline.fetch(:completeness).fetch(:ratio)).to eq("1.0")
    end

    it "can express a contiguous outage as device_not_reporting" do
      window = SyntheticHealth::AnalysisWindow.default
      outage = SyntheticHealth::TrajectoryScenario.null(
        seed: 3,
        missingness: SyntheticHealth::MissingnessPattern.outage(
          from: window.affected_start, to: window.affected_start + 4
        )
      )
      dark = outage.readings.reject(&:observed?)

      expect(dark.map(&:quality_state).uniq).to eq([ "device_not_reporting" ])
      expect(dark.map(&:local_date).uniq.size).to eq(5)
    end

    it "keeps raw readings, usable readings and analytical units separate (SC §6, STAT-004/005)" do
      affected = scenario.truth.realized_for(systolic).fetch(:phases).fetch(:affected)

      expect(affected.fetch(:raw_readings)).to be > affected.fetch(:observed_readings)
      expect(affected.fetch(:analytical_units)).to be <= affected.fetch(:observed_readings)
      expect(affected.fetch(:analytical_unit_dates).size).to eq(affected.fetch(:analytical_units))
    end
  end

  # ------------------------------------------------------------------
  # Instrumentation (STAT-007/008/009)
  # ------------------------------------------------------------------
  describe "the source-switch artifact" do
    subject(:scenario) { SyntheticHealth::Scenarios.build(:source_switch_artifact, seed: 4242) }

    it "moves the recorded numbers without touching the subject" do
      expect(scenario.latent_series).to eq(scenario.null_equivalent.latent_series)
      expect(scenario.truth).not_to be_biological_effect_present
      expect(scenario.truth.confounder_kinds).to eq([ :source_switch ])
    end

    it "reports the realized source mix rather than asserting what it means" do
      mix = scenario.truth.realized_for(systolic).fetch(:phases).fetch(:affected).fetch(:source_mix)

      expect(mix.fetch(:counts).keys).to contain_exactly("src_home_cuff", "src_replacement_cuff")
      expect(mix.fetch(:fractions).values.map { |f| BigDecimal(f) }.sum).to eq(BigDecimal(1))

      baseline_mix = scenario.truth.realized_for(systolic).fetch(:phases).fetch(:baseline).fetch(:source_mix)
      expect(baseline_mix.fetch(:counts).keys).to eq([ "src_home_cuff" ])
    end

    it "can overlay a real effect on the artifact without conflating them" do
      combined = SyntheticHealth::Scenarios.build(:source_switch_with_biology, seed: 4242)

      expect(combined.truth).to be_biological_effect_present
      expect(combined.truth.confounder_kinds).to eq([ :source_switch ])
      expect(combined.expected_effect.magnitude).to eq(BigDecimal(SyntheticHealth::Fixtures::LEVEL_SHIFT))
    end
  end

  # ------------------------------------------------------------------
  # Correlated families (SC §49–50, STAT-033/034)
  # ------------------------------------------------------------------
  describe "correlated dimensions" do
    subject(:scenario) { SyntheticHealth::Scenarios.build(:correlated_families, seed: 4242) }

    it "moves two dimensions from ONE declared cause" do
      causes = scenario.truth.effects.select(&:present?).map(&:cause).uniq

      expect(causes.size).to eq(1)
      expect(scenario.truth.effects.select(&:present?).map(&:semantic_key))
        .to contain_exactly(
          "health.vital.blood_pressure.systolic",
          "health.vital.blood_pressure.diastolic"
        )
      expect(scenario.semantic_families.values.uniq).to include("blood_pressure", "heart_rate")
    end

    it "leaves the independent family unmoved unless a second cause is injected" do
      expect(scenario.truth.effect_for("health.vital.pulse")).not_to be_present

      supported = SyntheticHealth::Scenarios.build(:correlated_families_with_independent_support, seed: 4242)
      expect(supported.truth.effect_for("health.vital.pulse")).to be_present
      expect(supported.truth.effects.select(&:present?).map(&:cause).uniq.size).to eq(2)
    end

    it "records that readings from one measurement event are one analytical unit" do
      expect(scenario.grouped_readings.values.map(&:size).uniq).to eq([ 3 ])
      expect(scenario.readings.map(&:group_key).uniq.size).to eq(scenario.opportunities.size)
    end

    it "names the derived dimensions that will share these families" do
      details = scenario.truth.confounder(:correlated_dimensions).details

      expect(details.fetch(:shared_semantic_family)).to eq("blood_pressure")
      expect(details.fetch(:derived_dimensions_expected_to_be_redundant))
        .to include("health.vital.blood_pressure.daily_summary")
    end
  end

  # ------------------------------------------------------------------
  # Coverage and shape
  # ------------------------------------------------------------------
  describe "scenario coverage" do
    it "covers every family HO §100 requires" do
      expect(SyntheticHealth::Scenarios::REQUIRED_FAMILIES).to contain_exactly(
        :null, :level_shift, :trend, :source_switch_artifact, :missingness_artifact,
        :sparse_outliers, :autocorrelation, :phase_drift, :correlated_families
      )
      expect(SyntheticHealth::Scenarios::REQUIRED_FAMILIES - SyntheticHealth::Scenarios::BUILDERS.keys).to be_empty
    end

    it "generates more artifact families than real-effect families" do
      without_effect = SyntheticHealth::Scenarios.without_injected_effect(seed: 4242).map(&:family)

      expect(without_effect).to include(
        :null, :source_switch_artifact, :missingness_artifact,
        :sparse_outliers, :autocorrelation, :phase_drift
      )
    end

    it "contaminates sparse outliers without labelling them in the data" do
      outliers = SyntheticHealth::Scenarios.build(:sparse_outliers, seed: 4242)
      injected = outliers.truth.confounder(:sparse_outliers).details.fetch(:injected)

      expect(injected.size).to eq(SyntheticHealth::Fixtures::OUTLIER_COUNT)
      expect(outliers.truth).not_to be_biological_effect_present
      # The contaminated readings must be indistinguishable from clean ones,
      # or robustness is untestable.
      expect(outliers.readings.map(&:quality_flags).uniq).to eq([ {} ])
    end

    it "samples one unchanged cyclic process at two phases" do
      drift = SyntheticHealth::Scenarios.build(:phase_drift, seed: 4242)

      expect(drift.truth).not_to be_biological_effect_present
      expect(drift.truth.confounder(:phase_drift).details.fetch(:period_days))
        .to be > drift.window.baseline_days
      expect(drift.truth.latent_median_delta(systolic).abs).to be_positive
    end

    it "generates correlated consecutive readings for the autocorrelation family" do
      autocorrelated = SyntheticHealth::Scenarios.build(:autocorrelation, seed: 4242)
      series = autocorrelated.latent_series.fetch(systolic)
      step_sizes = series.each_cons(2).map { |a, b| (b - a).abs }
      spread = series.max - series.min

      expect(autocorrelated.truth).not_to be_biological_effect_present
      # Consecutive readings move far less than the series' overall range —
      # the signature of dependence, and the reason a raw reading count
      # overstates the evidence (SC §27).
      expect(SyntheticHealth::Decimal.median(step_sizes)).to be < spread / 2
    end

    it "can build a window too short for a longitudinal claim (SC §23)" do
      small = SyntheticHealth::Scenarios.build(:small_sample, seed: 4242)

      expect(small.truth).to be_biological_effect_present
      expect(small.truth.analytical_units(systolic, :affected)).to be < 5
    end
  end

  # ------------------------------------------------------------------
  # Structural invariants
  # ------------------------------------------------------------------
  describe "reading invariants" do
    it "holds the observed/missing value invariant for every family" do
      SyntheticHealth::Scenarios.all(seed: 17).each do |scenario|
        expect { scenario.readings.each(&:validate!) }.not_to raise_error
      end
    end

    it "records subject-local dates even when the UTC date differs" do
      scenario = SyntheticHealth::Scenarios.build(:null, seed: 4242)
      evening = scenario.readings.find { |reading| reading.slot == "evening" }

      expect(evening.observed_at.utc.to_date).not_to eq(evening.local_date)
      expect(evening.local_date).to eq(scenario.subject.local_date(evening.observed_at))
    end

    it "gives every reading stable provenance fields" do
      scenario = SyntheticHealth::Scenarios.build(:source_switch_artifact, seed: 4242)

      expect(scenario.readings.map(&:source_record_id).uniq.size).to eq(scenario.readings.size)
      expect(scenario.readings.map(&:source_key).uniq.size).to eq(2)
      expect(scenario.readings).to all(have_attributes(subject_key: "subj_0001", semantic_version: 1))
    end

    # The harness duplicates the taxonomy so it can run without Rails. That
    # duplication is only safe if it is checked, so it is checked — against
    # the schema text, still with no database connection.
    it "matches the quality_state and recording_method values the schema allows" do
      structure = File.read(File.expand_path("../../db/structure.sql", __dir__))

      quality_states = structure[/observations_quality_state_check CHECK \(\(quality_state = ANY \(ARRAY\[(.+?)\]\)\)\)/m, 1]
      recording_methods = structure[/observations_recording_method_check CHECK \(\(recording_method = ANY \(ARRAY\[(.+?)\]\)\)\)/m, 1]

      expect(quality_states.scan(/'([a-z_]+)'::text/).flatten)
        .to match_array(SyntheticHealth::QualityStates::ALL)
      expect(recording_methods.scan(/'([a-z_]+)'::text/).flatten)
        .to match_array(SyntheticHealth::SyntheticSource::RECORDING_METHODS)
    end
  end
end
