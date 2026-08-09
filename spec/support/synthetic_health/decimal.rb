# frozen_string_literal: true

require "bigdecimal"

module SyntheticHealth
  # Measurement values are BigDecimal end to end — never Float.
  #
  # Two reasons, both load-bearing for a harness whose whole job is
  # reproducibility:
  #
  #   1. Canonical telemetry stores `numeric`, and a fixture that generates
  #      Floats would round-trip differently than it generated.
  #   2. Float arithmetic is only *practically* portable. BigDecimal
  #      arithmetic over integer draws is exactly portable, which is what
  #      "byte-identical output for the same seed" requires.
  #
  # Callers may pass Integer/Float/Rational/String for ergonomics; everything
  # is cast here, and Floats go through #to_s so `0.6` means six tenths rather
  # than 0.59999999999999997779553950749686919152736663818359375.
  module Decimal
    # Internal working precision. Intermediate results are rounded here so a
    # long chain of BigDecimal operations cannot grow unbounded digits and
    # make two equivalent computation orders disagree.
    PRECISION = 6

    module_function

    def cast(value)
      case value
      when nil then nil
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when Rational then BigDecimal(value, PRECISION + 12)
      when Float then BigDecimal(value.to_s)
      when String then BigDecimal(value)
      else
        raise ArgumentError, "cannot express #{value.inspect} (#{value.class}) as a measurement value"
      end
    end

    def zero
      BigDecimal(0)
    end

    def round(value, precision = PRECISION)
      cast(value).round(precision)
    end

    # SC §29: the default descriptive summary of a continuous dimension is the
    # median. Used here only to describe what was generated — the harness
    # states no opinion about whether a difference between two medians means
    # anything. That judgement belongs to the engine.
    def median(values)
      return nil if values.empty?

      sorted = values.map { |v| cast(v) }.sort
      mid = sorted.size / 2
      return sorted[mid] if sorted.size.odd?

      round((sorted[mid - 1] + sorted[mid]) / 2)
    end

    # Median absolute deviation. Descriptive only, same caveat as #median.
    def mad(values)
      centre = median(values)
      return nil if centre.nil?

      median(values.map { |v| (cast(v) - centre).abs })
    end

    def ratio(numerator, denominator)
      return nil if denominator.nil? || denominator.zero?

      round(cast(numerator) / cast(denominator))
    end
  end
end
