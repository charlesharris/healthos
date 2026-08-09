# frozen_string_literal: true

require_relative "decimal"
require_relative "randomness"

module SyntheticHealth
  # The latent value series for one dimension: a sum of named components.
  #
  # "Latent" means *before* instrumentation and *before* missingness. That
  # layering is the whole point. A source-switch scenario and a null scenario
  # built from the same seed share a byte-identical latent series, so the
  # difference between their recorded values is provably the instrument and
  # nothing else. Likewise a missingness scenario removes readings from an
  # unchanged biology. Ground truth stops being an assertion about the
  # generator and becomes a property of it.
  #
  # Two rules make that work:
  #
  #   1. Each stochastic component draws from its own labelled stream, so
  #      adding a deterministic component (a level shift, say) does not shift
  #      any noise draw.
  #   2. Deterministic components consume no randomness at all. Therefore
  #      `latent(level_shift) - latent(null)` equals the injected magnitude
  #      exactly, for every index, with no tolerance.
  class ValueProcess
    Context = Struct.new(:opportunities, :streams, :label_prefix, :window, keyword_init: true) do
      def size
        opportunities.size
      end

      def stream(label)
        streams.for("#{label_prefix}|#{label}")
      end
    end

    # Base class for every additive contribution to a value series.
    class Component
      attr_reader :stream_label

      def initialize(label:)
        @stream_label = label
      end

      # => Array<BigDecimal>, one per opportunity.
      def series(context)
        raise NotImplementedError
      end

      def to_h
        raise NotImplementedError
      end
    end

    # Constant level. The "where the subject normally sits" term.
    class Level < Component
      def initialize(value:, label: "level")
        @value = Decimal.cast(value)
        super(label: label)
      end

      def series(context)
        Array.new(context.size) { @value }
      end

      def to_h
        { component: "level", value: @value.to_s("F") }
      end
    end

    # A sustained step. Genuine biology in the level-shift family; also used
    # to overlay a real effect on top of an artifact.
    class LevelShift < Component
      attr_reader :magnitude

      def initialize(magnitude:, phase: :affected, onset_date: nil, label: "level_shift")
        @magnitude = Decimal.cast(magnitude)
        @phase = phase
        @onset_date = onset_date
        super(label: label)
      end

      def series(context)
        context.opportunities.map { |opportunity| applies?(opportunity) ? @magnitude : Decimal.zero }
      end

      def onset_date_for(window)
        @onset_date || window.dates_for(@phase).first
      end

      def to_h
        { component: "level_shift", magnitude: @magnitude.to_s("F"), phase: @phase, onset_date: @onset_date&.iso8601 }
      end

      private

      def applies?(opportunity)
        return opportunity.local_date >= @onset_date if @onset_date

        opportunity.phase == @phase
      end
    end

    # A gradual drift rather than a step. Distinguishing the two matters: a
    # trend and a shift of the same total magnitude are different clinical
    # stories and different Difference kinds (SC §33).
    class LinearTrend < Component
      attr_reader :slope_per_day

      def initialize(slope_per_day:, phase: :affected, onset_date: nil, label: "linear_trend")
        @slope_per_day = Decimal.cast(slope_per_day)
        @phase = phase
        @onset_date = onset_date
        super(label: label)
      end

      def series(context)
        onset = onset_date_for(context.window)

        context.opportunities.map do |opportunity|
          elapsed = (opportunity.local_date - onset).to_i
          elapsed.negative? ? Decimal.zero : Decimal.round(@slope_per_day * elapsed)
        end
      end

      def onset_date_for(window)
        @onset_date || window.dates_for(@phase).first
      end

      # Total drift accumulated by the end of the window it starts in.
      def total_change_over(days)
        Decimal.round(@slope_per_day * (days - 1))
      end

      def to_h
        {
          component: "linear_trend", slope_per_day: @slope_per_day.to_s("F"),
          phase: @phase, onset_date: @onset_date&.iso8601
        }
      end
    end

    # Independent measurement-to-measurement noise.
    class WhiteNoise < Component
      attr_reader :scale

      def initialize(scale:, label: "white_noise")
        @scale = Decimal.cast(scale)
        super(label: label)
      end

      def series(context)
        rng = context.stream(stream_label)
        Array.new(context.size) { Deviates.noise(rng, @scale) }
      end

      def to_h
        { component: "white_noise", scale: @scale.to_s("F") }
      end
    end

    # AR(1) noise: each reading is mostly yesterday's reading.
    #
    # This is the counterexample the autocorrelation family exists to
    # provide (SC §27). Correlated samples carry far less information than
    # their count suggests, so any method treating each reading as
    # independent evidence will over-call a difference that is only drift in
    # a stationary process.
    class Ar1Noise < Component
      attr_reader :phi, :innovation_scale

      def initialize(phi:, innovation_scale:, burn_in: 40, label: "ar1_noise")
        @phi = Decimal.cast(phi)
        @innovation_scale = Decimal.cast(innovation_scale)
        @burn_in = burn_in
        super(label: label)
      end

      def series(context)
        rng = context.stream(stream_label)
        state = Decimal.zero

        # Burn in so the series does not start artificially at the mean.
        @burn_in.times { state = step(state, rng) }

        Array.new(context.size) do
          state = step(state, rng)
          state
        end
      end

      def to_h
        {
          component: "ar1_noise", phi: @phi.to_s("F"),
          innovation_scale: @innovation_scale.to_s("F"), burn_in: @burn_in
        }
      end

      private

      def step(state, rng)
        Decimal.round((state * @phi) + Deviates.noise(rng, @innovation_scale))
      end
    end

    # A slow cyclic component — season, medication cycle, rehab phase.
    #
    # With a period longer than the baseline window, baseline and affected
    # sample different phases of one unchanged process. A window comparison
    # will see a real numeric difference that is nonetheless not a change:
    # exactly the nonstationarity SC §62–63 says a trailing baseline handles
    # badly.
    #
    # Built from a twelve-point table with linear interpolation rather than
    # Math.sin, because the harness does exact BigDecimal arithmetic and does
    # not depend on the platform's libm.
    class SeasonalWave < Component
      # sin(0°), sin(30°) ... sin(330°), to four places.
      TABLE = [
        "0", "0.5", "0.866", "1", "0.866", "0.5",
        "0", "-0.5", "-0.866", "-1", "-0.866", "-0.5"
      ].map { |value| BigDecimal(value) }.freeze

      attr_reader :amplitude, :period_days

      def initialize(amplitude:, period_days:, phase_offset_days: 0, label: "seasonal_wave")
        raise ArgumentError, "period_days must be positive" unless period_days.positive?

        @amplitude = Decimal.cast(amplitude)
        @period_days = period_days
        @phase_offset_days = phase_offset_days
        super(label: label)
      end

      def series(context)
        context.opportunities.map { |opportunity| value_at(opportunity.day_index) }
      end

      def value_at(day_index)
        position = Decimal.round(Decimal.cast(day_index + @phase_offset_days) * TABLE.size / @period_days)
        lower = position.floor.to_i % TABLE.size
        fraction = position - position.floor
        upper = (lower + 1) % TABLE.size

        Decimal.round(@amplitude * (TABLE[lower] + ((TABLE[upper] - TABLE[lower]) * fraction)))
      end

      def to_h
        {
          component: "seasonal_wave", amplitude: @amplitude.to_s("F"),
          period_days: @period_days, phase_offset_days: @phase_offset_days
        }
      end
    end

    # A handful of implausible readings: mis-cuffed arm, transcription slip,
    # a device reporting garbage once.
    #
    # Only expected opportunities are contaminated — a reading that never
    # happened cannot be an outlier. The chosen indices are recorded in ground
    # truth but NOT flagged on the Readings themselves: telling the engine
    # which values are contaminated would make robustness untestable.
    class Outliers < Component
      attr_reader :count, :magnitude

      def initialize(count:, magnitude:, sign: :both, label: "outliers")
        @count = count
        @magnitude = Decimal.cast(magnitude)
        @sign = sign
        @injected = []
        super(label: label)
      end

      def series(context)
        rng = context.stream(stream_label)
        eligible = context.opportunities.each_index.select { |index| context.opportunities[index].expected? }
        chosen = Deviates.sample_indices(rng, count: @count, from: eligible)

        deltas = Array.new(context.size) { Decimal.zero }
        @injected = chosen.map do |index|
          delta = signed(rng)
          deltas[index] = delta
          {
            index: index,
            local_date: context.opportunities[index].local_date.iso8601,
            phase: context.opportunities[index].phase,
            delta: delta.to_s("F")
          }
        end

        deltas
      end

      def injected
        @injected
      end

      def to_h
        { component: "outliers", count: @count, magnitude: @magnitude.to_s("F"), sign: @sign, injected: @injected }
      end

      private

      def signed(rng)
        case @sign
        when :positive then @magnitude
        when :negative then -@magnitude
        else Deviates.chance?(rng, "0.5") ? @magnitude : -@magnitude
        end
      end
    end

    attr_reader :components

    def initialize(components)
      duplicated = components.map(&:stream_label).tally.select { |_label, count| count > 1 }.keys
      unless duplicated.empty?
        raise ArgumentError,
          "duplicate component stream labels #{duplicated.join(', ')}: each component needs its own " \
          "stream or determinism guarantees break down"
      end

      @components = components.freeze
    end

    def series(context)
      contributions = @components.map { |component| component.series(context) }

      Array.new(context.size) do |index|
        Decimal.round(contributions.sum { |contribution| contribution[index] })
      end
    end

    def component(kind)
      @components.find { |candidate| candidate.to_h[:component] == kind.to_s }
    end

    def to_h
      @components.map(&:to_h)
    end
  end
end
