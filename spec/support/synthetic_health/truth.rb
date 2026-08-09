# frozen_string_literal: true

require_relative "decimal"
require_relative "quality_states"

module SyntheticHealth
  # What was actually injected into a scenario.
  #
  # `kind: :none` is a first-class answer, not a null object of convenience:
  # the null family genuinely injects nothing, and a spec asserting that
  # should read as an assertion rather than as an absence of one.
  Effect = Struct.new(
    :kind,
    :semantic_key,
    :magnitude,
    :unit,
    :direction,
    :phase,
    :slope_per_day,
    :cause,
    :details,
    keyword_init: true
  ) do
    def self.none(semantic_key: nil)
      new(kind: :none, semantic_key: semantic_key, magnitude: Decimal.zero, direction: :none, details: {})
    end

    def present?
      kind != :none
    end

    def to_h
      super.merge(
        magnitude: magnitude&.to_s("F"),
        slope_per_day: slope_per_day&.to_s("F")
      ).compact
    end
  end

  # Something in the generated data that is NOT a change in the subject:
  # an instrument swap, an adherence collapse, contamination, correlation
  # structure, a cycle sampled at two different phases.
  #
  # Kept separate from Effect on purpose. "Was there a real effect?" and "was
  # there something that will look like one?" are different questions, and
  # every artifact family in HO §100 is a case where the honest answer to the
  # first is no.
  Confounder = Struct.new(:kind, :semantic_keys, :details, keyword_init: true) do
    def to_h
      super.merge(details: details || {})
    end
  end

  # Descriptive summary of what a generated timeline contains.
  #
  # Counts, denominators and medians only. No gate is applied and no verdict
  # is reached — completeness is reported as a ratio WITH its numerator and
  # denominator (STAT-011/021) precisely so that a spec asserts against what
  # was generated rather than against a number someone typed into the spec.
  #
  # Note the three separate counts (SC §6): raw readings, usable readings, and
  # analytical units. `42 readings → 12 measurement days` must stay visible,
  # because the whole point of STAT-004/005 is that they are not the same n.
  class RealizedSummary
    PHASES = %i[baseline gap affected].freeze

    def self.for(readings:, window:, dimensions:)
      new(readings: readings, window: window, dimensions: dimensions).to_h
    end

    def initialize(readings:, window:, dimensions:)
      @readings = readings
      @window = window
      @dimensions = dimensions
    end

    def to_h
      @dimensions.to_h do |dimension|
        for_dimension = @readings.select { |reading| reading.semantic_key == dimension.semantic_key }

        [
          dimension.semantic_key,
          {
            families: dimension.families,
            unit: dimension.unit,
            phases: PHASES.to_h { |phase| [ phase, summarize(for_dimension.select { |r| r.phase == phase }) ] }
          }
        ]
      end
    end

    private

    def summarize(readings)
      observed = readings.select(&:observed?)
      expected = readings.select(&:expected?)
      values = observed.map(&:value)

      {
        raw_readings: readings.size,
        expected_opportunities: expected.size,
        not_expected: readings.size - expected.size,
        observed_readings: observed.size,
        missing_readings: readings.size - observed.size,
        missing_by_state: missing_by_state(readings),
        # SC §14: the ratio is never enough on its own; the denominator ships
        # with it, always.
        completeness: {
          usable: observed.size,
          expected: expected.size,
          ratio: Decimal.ratio(observed.size, expected.size)&.to_s("F")
        },
        # SC §5–6. Days with at least one usable reading — the analytical unit
        # for a day-based comparison, and emphatically not the reading count.
        analytical_units: observed.map(&:local_date).uniq.size,
        analytical_unit_dates: observed.map(&:local_date).uniq.sort.map(&:iso8601),
        calendar_span_days: calendar_span(observed),
        source_mix: source_mix(observed),
        median: Decimal.median(values)&.to_s("F"),
        mad: Decimal.mad(values)&.to_s("F"),
        minimum: values.min&.to_s("F"),
        maximum: values.max&.to_s("F")
      }
    end

    def missing_by_state(readings)
      readings.reject(&:observed?).group_by(&:quality_state).transform_values(&:size).sort.to_h
    end

    def calendar_span(observed)
      dates = observed.map(&:local_date)
      return 0 if dates.empty?

      (dates.max - dates.min).to_i + 1
    end

    # SC §10–11: which instruments contributed, and in what proportion. The
    # engine decides what a mixed window means; the harness only reports the
    # mix it produced.
    def source_mix(observed)
      counts = observed.group_by(&:source_key).transform_values(&:size).sort.to_h

      {
        counts: counts,
        fractions: counts.transform_values { |count| Decimal.ratio(count, observed.size)&.to_s("F") }
      }
    end
  end

  # Everything a spec needs to know about what a scenario generated, without
  # having to reverse-engineer it from the readings.
  #
  # This is the artifact that makes the harness an acceptance instrument
  # rather than a fixture factory: engine specs assert against `truth`, so
  # they state "the engine recovered what was injected" rather than "the
  # engine produced 12.4".
  class Truth
    attr_reader :family, :seed, :subject, :window, :schedule, :dimensions,
      :effects, :confounders, :process, :realized, :latent, :notes

    def initialize(family:,
                   seed:,
                   subject:,
                   window:,
                   schedule:,
                   dimensions:,
                   effects:,
                   confounders:,
                   process:,
                   realized:,
                   latent:,
                   notes: [])
      @family = family
      @seed = seed
      @subject = subject
      @window = window
      @schedule = schedule
      @dimensions = dimensions
      @effects = effects.freeze
      @confounders = confounders.freeze
      @process = process.freeze
      @realized = realized.freeze
      @latent = latent.freeze
      @notes = notes.freeze
    end

    # Was a genuine change in the subject injected? The artifact families
    # answer `false`, and that is the point of them.
    def biological_effect_present?
      @effects.any?(&:present?)
    end

    def primary_effect
      @effects.find(&:present?) || @effects.first || Effect.none
    end

    def effect_for(semantic_key)
      @effects.find { |effect| effect.semantic_key == semantic_key && effect.present? } ||
        Effect.none(semantic_key: semantic_key)
    end

    def confounder(kind)
      @confounders.find { |candidate| candidate.kind == kind }
    end

    def confounder_kinds
      @confounders.map(&:kind)
    end

    def realized_for(semantic_key)
      @realized.fetch(semantic_key)
    end

    def completeness(semantic_key, phase)
      realized_for(semantic_key).fetch(:phases).fetch(phase).fetch(:completeness)
    end

    def analytical_units(semantic_key, phase)
      realized_for(semantic_key).fetch(:phases).fetch(phase).fetch(:analytical_units)
    end

    # Median of the LATENT series per phase — the underlying process, before
    # instrumentation and before anything went missing.
    #
    # This is how an artifact scenario proves it is an artifact: the recorded
    # medians move, and these do not.
    def latent_median(semantic_key, phase)
      Decimal.median(latent_values(semantic_key, phase))
    end

    def latent_median_delta(semantic_key)
      baseline = latent_median(semantic_key, :baseline)
      affected = latent_median(semantic_key, :affected)
      return nil if baseline.nil? || affected.nil?

      Decimal.round(affected - baseline)
    end

    def latent_values(semantic_key, phase)
      @latent.fetch(semantic_key).select { |entry| entry.fetch(:phase) == phase }.map { |entry| entry.fetch(:value) }
    end

    def to_h
      {
        family: @family,
        seed: @seed,
        subject: @subject.to_h,
        window: @window.to_h,
        schedule: @schedule.to_h,
        dimensions: @dimensions.to_h { |dimension| [ dimension.semantic_key, dimension.families ] },
        biological_effect_present: biological_effect_present?,
        effects: @effects.map(&:to_h),
        confounders: @confounders.map(&:to_h),
        process: @process,
        realized: @realized,
        notes: @notes
      }
    end
  end
end
