# frozen_string_literal: true

require_relative "decimal"
require_relative "quality_states"
require_relative "randomness"

module SyntheticHealth
  # How an opportunity fails to produce a measurement.
  #
  # A pattern returns a quality_state for every opportunity it is asked
  # about — `observed` or one of the nine absence states. It never returns
  # nil, never returns a boolean, and never causes a Reading to be dropped.
  # Missingness in this harness is always a recorded fact with a stated
  # reason (SC §12, STAT-002/010).
  #
  # Determinism note: every subclass draws the SAME number of integers from
  # the stream on every call, whatever it decides. Branching on a draw and
  # then skipping the next draw would make the stream position depend on
  # earlier outcomes, and two scenarios differing only in a rate would
  # de-synchronise. Uniform consumption keeps them comparable.
  class MissingnessPattern
    # Sensible absence reasons for a device-mediated measurement. Weighted so
    # a timeline contains several distinct states rather than one repeated
    # one — a taxonomy that is never exercised is a taxonomy that rots.
    DEFAULT_STATES = {
      QualityStates::EXPECTED_BUT_MISSING => 5,
      QualityStates::DEVICE_NOT_REPORTING => 3,
      QualityStates::SOURCE_UNAVAILABLE => 1,
      QualityStates::MANUAL_ENTRY_ABSENT => 1
    }.freeze

    def self.none
      None.new
    end

    def self.uniform(rate:, states: DEFAULT_STATES)
      Uniform.new(rate: rate, states: states)
    end

    # Different dropout rates per phase — the generator behind differential
    # missingness (SC §16). The harness supplies the two rates; whether the
    # resulting completeness delta means anything is the engine's call.
    def self.by_phase(rates:, states: DEFAULT_STATES)
      PhaseRates.new(rates: rates, states: states)
    end

    # A contiguous outage. Distinct from random dropout: a dead device for
    # nine days is a different measurement-behaviour story from nine days
    # missed at random, and the two must be distinguishable in the data.
    def self.outage(from:, to:, state: QualityStates::DEVICE_NOT_REPORTING, rate: 1)
      Outage.new(from: from, to: to, state: state, rate: rate)
    end

    # Present in the payload but unusable (SC §12 `invalid_measurement`).
    def self.invalid_readings(rate:)
      Uniform.new(rate: rate, states: { QualityStates::INVALID_MEASUREMENT => 1 })
    end

    # Data that will arrive later. Lets a scenario stage the late-data path
    # (STAT-040/041) without mutating anything.
    def self.late_arriving(from:, to:, rate: 1)
      Outage.new(from: from, to: to, state: QualityStates::LATE_NOT_YET_ARRIVED, rate: rate)
    end

    def self.composite(*patterns)
      Composite.new(patterns.flatten)
    end

    def state_for(opportunity:, rng:)
      raise NotImplementedError
    end

    def to_h
      raise NotImplementedError
    end

    private

    # One rate draw plus one state draw, always, whatever the answer.
    def resolve(rng:, rate:, states:, applicable:)
      dropped = Deviates.chance?(rng, rate)
      candidate = Deviates.weighted_pick(rng, states)

      applicable && dropped ? QualityStates.validate!(candidate) : QualityStates::OBSERVED
    end

    def normalize_states(states)
      states.each_key { |state| QualityStates.validate!(state) }
      states.freeze
    end

    class None < MissingnessPattern
      def state_for(opportunity:, rng:)
        QualityStates::OBSERVED
      end

      def to_h
        { pattern: "none" }
      end
    end

    class Uniform < MissingnessPattern
      attr_reader :rate, :states

      def initialize(rate:, states: DEFAULT_STATES)
        @rate = Decimal.cast(rate)
        @states = normalize_states(states)
        freeze
      end

      def state_for(opportunity:, rng:)
        resolve(rng: rng, rate: @rate, states: @states, applicable: true)
      end

      def to_h
        { pattern: "uniform", rate: @rate.to_s("F"), states: @states }
      end
    end

    class PhaseRates < MissingnessPattern
      attr_reader :rates, :states

      def initialize(rates:, states: DEFAULT_STATES)
        @rates = rates.transform_values { |rate| Decimal.cast(rate) }.freeze
        @states = normalize_states(states)
        freeze
      end

      def state_for(opportunity:, rng:)
        rate = @rates.fetch(opportunity.phase, Decimal.zero)
        resolve(rng: rng, rate: rate, states: @states, applicable: true)
      end

      def to_h
        { pattern: "by_phase", rates: @rates.transform_values { |r| r.to_s("F") }, states: @states }
      end
    end

    class Outage < MissingnessPattern
      attr_reader :from, :to, :state, :rate

      def initialize(from:, to:, state: QualityStates::DEVICE_NOT_REPORTING, rate: 1)
        @from = from
        @to = to
        @state = QualityStates.validate!(state)
        @rate = Decimal.cast(rate)
        freeze
      end

      def state_for(opportunity:, rng:)
        within = opportunity.local_date >= @from && opportunity.local_date <= @to
        resolve(rng: rng, rate: @rate, states: { @state => 1 }, applicable: within)
      end

      def to_h
        { pattern: "outage", from: @from.iso8601, to: @to.iso8601, state: @state, rate: @rate.to_s("F") }
      end
    end

    # Layered patterns. Every child is consulted for every opportunity (so
    # stream positions never depend on which one fired first) and the first
    # non-observed answer wins.
    class Composite < MissingnessPattern
      attr_reader :patterns

      def initialize(patterns)
        @patterns = patterns.freeze
        freeze
      end

      def state_for(opportunity:, rng:)
        answers = @patterns.map { |pattern| pattern.state_for(opportunity: opportunity, rng: rng) }
        answers.find { |state| state != QualityStates::OBSERVED } || QualityStates::OBSERVED
      end

      def to_h
        { pattern: "composite", patterns: @patterns.map(&:to_h) }
      end
    end
  end
end
