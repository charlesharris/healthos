# frozen_string_literal: true

require_relative "analysis_window"
require_relative "dimensions"
require_relative "measurement_schedule"
require_relative "missingness_pattern"
require_relative "randomness"
require_relative "reading"
require_relative "source_plan"
require_relative "synthetic_source"
require_relative "synthetic_subject"
require_relative "timeline_builder"
require_relative "truth"
require_relative "value_process"

module SyntheticHealth
  # Base class for every scenario family.
  #
  # A scenario is: an explicit integer seed, a population of one subject, a
  # window, a protocol, one or more dimensions with a value process each, an
  # instrumentation plan, a missingness pattern — and a statement of what was
  # injected.
  #
  # Two contracts every subclass inherits:
  #
  #   * DETERMINISM. The seed is required and must be an Integer. All
  #     randomness flows through SeedStreams. `#digest` exists so a spec can
  #     assert byte-identical output rather than "looks the same".
  #   * GROUND TRUTH. `#truth` reports what was injected and what was
  #     generated. Nothing in a scenario judges the data: there is no
  #     `#significant?`, no `#should_be_detected`, no threshold. Whether the
  #     engine ought to call a given difference is governed configuration
  #     under statistical review (STAT-044), and a fixture that quietly
  #     encoded its own opinion would be marking its own homework.
  class Scenario
    attr_reader :family, :seed, :subject, :window, :schedule, :dimensions,
      :source_plan, :missingness, :streams, :notes

    def initialize(family:,
                   seed:,
                   dimensions:,
                   processes:,
                   subject: nil,
                   window: nil,
                   schedule: nil,
                   source_plan: nil,
                   missingness: nil,
                   effects: [],
                   confounders: [],
                   notes: [])
      @family = family
      @streams = SeedStreams.new(seed)
      @seed = @streams.seed
      @dimensions = Array(dimensions).freeze
      @processes = processes
      @subject = subject || SyntheticSubject.default
      @window = window || AnalysisWindow.default
      @schedule = schedule || MeasurementSchedule.twice_daily
      @source_plan = source_plan || SourcePlan.constant(SyntheticSource.home_cuff)
      @missingness = missingness || MissingnessPattern.none
      @declared_effects = Array(effects).freeze
      @declared_confounders = Array(confounders).freeze
      @notes = Array(notes).freeze
    end

    def builder
      @builder ||= TimelineBuilder.new(
        subject: @subject,
        window: @window,
        schedule: @schedule,
        dimensions: @dimensions,
        processes: @processes,
        source_plan: @source_plan,
        missingness: @missingness,
        streams: @streams
      )
    end

    # Plain data. Engine specs decide whether these become Observation rows,
    # an import file, or in-memory inputs.
    def readings
      builder.readings
    end

    def readings_for(semantic_key)
      builder.readings_for(semantic_key)
    end

    def opportunities
      builder.opportunities
    end

    def latent_series
      builder.latent_series
    end

    def primary_dimension
      @dimensions.first
    end

    def primary_semantic_key
      primary_dimension.semantic_key
    end

    def truth
      @truth ||= begin
        # Readings must exist first: components that make random choices
        # (contamination indices, for instance) only know what they chose once
        # the series has been generated.
        readings

        Truth.new(
          family: @family,
          seed: @seed,
          subject: @subject,
          window: @window,
          schedule: @schedule,
          dimensions: @dimensions,
          effects: effects,
          confounders: confounders,
          process: @processes.transform_values(&:to_h),
          realized: RealizedSummary.for(readings: readings, window: @window, dimensions: @dimensions),
          latent: latent_with_phases,
          notes: @notes
        )
      end
    end

    # The injected effect on the primary dimension. `Effect#present?` is false
    # for every artifact family and for null.
    def expected_effect
      truth.primary_effect
    end

    def effects
      return @declared_effects unless @declared_effects.empty?

      [ Effect.none(semantic_key: primary_semantic_key) ]
    end

    def confounders
      @declared_confounders
    end

    # SHA-256 over a canonical field-ordered serialisation of every Reading.
    # The determinism assertion in the harness spec is made against this.
    def digest
      Serialization.digest(readings)
    end

    def to_h(include_readings: false)
      base = {
        family: @family,
        seed: @seed,
        digest: digest,
        truth: truth.to_h
      }
      return base unless include_readings

      base.merge(readings: readings.map(&:to_h))
    end

    private

    def latent_with_phases
      latent_series.transform_values do |values|
        opportunities.each_with_index.map do |opportunity, index|
          {
            index: index,
            local_date: opportunity.local_date,
            phase: opportunity.phase,
            expected: opportunity.expected?,
            value: values[index]
          }
        end
      end
    end
  end
end
