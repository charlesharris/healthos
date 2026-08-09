# frozen_string_literal: true

# Synthetic health simulation harness — HO §100, epic 003-01.
#
# The acceptance instrument for the statistical engine. Built before the
# engine on purpose (003-01: "Build this before the engine; it is the engine's
# acceptance instrument"), and named in prototype-scope.md as the single
# artifact that survives into v2 — so it is written to be portable, not
# disposable.
#
# WHAT IT PRODUCES
#
#   Plain data. Structs of BigDecimals, Times, Dates and Strings. No
#   ActiveRecord, no Rails, no database — `require`-ing this file is enough.
#   Engine specs decide how to persist a timeline; the harness only describes
#   what a source would have said.
#
# THE FOUR GUARANTEES
#
#   1. Deterministic. Every scenario takes an explicit Integer seed. All
#      randomness comes from `Random.new(seed)` via SeedStreams; nothing
#      touches the global RNG, and all arithmetic is exact BigDecimal over
#      integer draws, so output is reproducible across processes and
#      platforms — not merely stable on one machine. `Scenario#digest` makes
#      that assertable.
#
#   2. No silent gaps, no zero-imputation. Every measurement opportunity
#      produces exactly one Reading per dimension, carrying a state from the
#      ten-state SC §12 taxonomy. Missing readings carry no value and no
#      unit — never a zero standing in for absence (STAT-002).
#
#   3. Layered, so ground truth is structural. Biology is generated first,
#      then instrumentation is applied, then missingness. An artifact scenario
#      and a null scenario at the same seed share a byte-identical latent
#      series, so "the subject did not change" is a property of the generator
#      rather than a hope about it.
#
#   4. No thresholds. The harness generates data with known ground truth and
#      reports what it generated. It never decides what counts as a shift,
#      adequate completeness, or invalidating instrumentation. Those are
#      governed configuration under statistical review (STAT-044). Fixture
#      magnitudes live in `Fixtures` and are labelled NON-CLINICAL (HO §175);
#      specs assert against `scenario.truth`, never against those constants.
#
# USAGE
#
#   scenario = SyntheticHealth::Scenarios.build(:level_shift, seed: 4242)
#   scenario.readings          # => Array<SyntheticHealth::Reading>
#   scenario.expected_effect   # => Effect(kind: :level_shift, magnitude: 12)
#   scenario.truth.realized    # counts, denominators, medians, source mix
#   scenario.digest            # stable across processes for a given seed
#
#   SyntheticHealth::Scenarios::REQUIRED_FAMILIES  # the HO §100 nine
#
# This file is a convenience loader. Every component also require_relatives
# its own dependencies, so `spec/rails_helper.rb`'s alphabetical glob over
# `spec/support/**/*.rb` loads them in any order without breaking.

require_relative "analysis_window"
require_relative "correlated_dimensions_scenario"
require_relative "decimal"
require_relative "dimensions"
require_relative "fixtures"
require_relative "measurement_schedule"
require_relative "missingness_pattern"
require_relative "quality_states"
require_relative "randomness"
require_relative "reading"
require_relative "scenario"
require_relative "scenarios"
require_relative "source_plan"
require_relative "source_switch_scenario"
require_relative "synthetic_source"
require_relative "synthetic_subject"
require_relative "timeline_builder"
require_relative "trajectory_scenario"
require_relative "truth"
require_relative "value_process"
