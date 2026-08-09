# frozen_string_literal: true

require_relative "decimal"

module SyntheticHealth
  # Named, independent random streams derived from one explicit integer seed.
  #
  # Determinism is the harness's central promise. A flaky generator would make
  # every downstream statistical failure unreproducible, so:
  #
  #   * every scenario takes an explicit Integer seed;
  #   * randomness comes only from `Random.new(...)`, never `Kernel#rand`,
  #     `Random.rand`, `Array#sample` without a generator, or anything else
  #     touching the global RNG;
  #   * each concern (values, missingness, outliers, instrumentation) draws
  #     from its OWN stream, so adding missingness to a scenario cannot
  #     perturb the biological series it is layered onto. That property is
  #     what lets a spec assert "the latent biology is byte-identical with and
  #     without the artifact" — the cleanest possible statement of ground
  #     truth for an artifact scenario.
  #
  # Stream seeds are derived with FNV-1a rather than String#hash, because
  # String#hash is salted per process and would silently destroy
  # cross-process reproducibility.
  class SeedStreams
    FNV_OFFSET_BASIS = 0xcbf29ce484222325
    FNV_PRIME = 0x100000001b3
    MASK64 = 0xFFFFFFFFFFFFFFFF

    attr_reader :seed

    def initialize(seed)
      unless seed.is_a?(Integer)
        raise ArgumentError, "seed must be an Integer (got #{seed.inspect}); scenarios are never implicitly seeded"
      end

      @seed = seed
      @streams = {}
    end

    # Memoised: a given label always names the same continuing stream within
    # one SeedStreams instance.
    def for(label)
      @streams[label.to_s] ||= Random.new(self.class.derive(@seed, label.to_s))
    end

    def labels
      @streams.keys.sort
    end

    def self.derive(seed, label)
      hash = FNV_OFFSET_BASIS
      "#{seed}:#{label}".each_byte do |byte|
        hash = ((hash ^ byte) * FNV_PRIME) & MASK64
      end
      hash
    end
  end

  # Random deviates built only from integer draws and exact BigDecimal
  # arithmetic. No Math.log / Math.cos / Float accumulation anywhere, so the
  # output is identical on any platform, not merely on this one.
  module Deviates
    # Irwin–Hall: the sum of twelve uniform draws is approximately normal with
    # unit variance once centred and scaled. Good enough for measurement
    # noise, and exactly reproducible, which Box–Muller is not.
    UNIFORM_STEPS = 1_000
    SUMMANDS = 12
    PROBABILITY_RESOLUTION = 1_000_000

    module_function

    # ~N(0, 1), bounded to [-6, 6].
    def standard(rng)
      total = 0
      SUMMANDS.times { total += rng.rand(0..UNIFORM_STEPS) }
      Decimal.round(BigDecimal(total - (SUMMANDS * UNIFORM_STEPS / 2)) / UNIFORM_STEPS)
    end

    # A noise draw with the given scale (standard-deviation-like).
    def noise(rng, scale)
      Decimal.round(standard(rng) * Decimal.cast(scale))
    end

    # Bernoulli draw. Always consumes exactly one integer from the stream, so
    # callers can draw unconditionally and keep stream alignment.
    def chance?(rng, probability)
      threshold = (Decimal.cast(probability) * PROBABILITY_RESOLUTION).round.to_i
      rng.rand(0...PROBABILITY_RESOLUTION) < threshold
    end

    # Weighted pick over a { value => weight } hash. Always consumes exactly
    # one integer.
    def weighted_pick(rng, weighted)
      entries = weighted.to_a.map { |value, weight| [ value, (Decimal.cast(weight) * PROBABILITY_RESOLUTION).round.to_i ] }
      total = entries.sum(&:last)
      raise ArgumentError, "weights must sum to a positive number: #{weighted.inspect}" unless total.positive?

      draw = rng.rand(0...total)
      running = 0
      entries.each do |value, weight|
        running += weight
        return value if draw < running
      end
      entries.last.first
    end

    # Distinct indices, deterministically chosen.
    def sample_indices(rng, count:, from:)
      pool = from.to_a
      return pool.sort if count >= pool.size

      pool.shuffle(random: rng).first(count).sort
    end
  end
end
