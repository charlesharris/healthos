# frozen_string_literal: true

require "date"
require "digest"
require "time"

require_relative "decimal"
require_relative "quality_states"

module SyntheticHealth
  # One generated measurement opportunity for one dimension.
  #
  # Deliberately plain data: a Struct of primitives, BigDecimals, Times and
  # Dates. No ActiveRecord, no Rails, no database. Engine specs decide how to
  # persist these (Observation rows, in-memory doubles, CSV for a fixture
  # import); the harness only describes what a source would have said.
  #
  # The observed/missing invariant mirrors the `observations` CHECK
  # constraints exactly: an observed Reading carries a value AND a unit, and a
  # missing Reading carries neither. There is no `value_or_zero` here for the
  # same reason there is none on Observation (STAT-002).
  Reading = Struct.new(
    :sequence,
    :subject_key,
    :semantic_key,
    :semantic_version,
    :value,
    :unit,
    :observed_at,
    :local_date,
    :timezone_offset_minutes,
    :quality_state,
    :quality_flags,
    :source_key,
    :source_type,
    :device_key,
    :recording_method,
    :measurement_protocol,
    :group_key,
    :source_record_id,
    :slot,
    :phase,
    keyword_init: true
  ) do
    def observed?
      QualityStates.observed?(quality_state)
    end

    def missing?
      !observed?
    end

    # Participates in the completeness denominator (SC §14).
    def expected?
      QualityStates.expected?(quality_state)
    end

    def validate!
      QualityStates.validate!(quality_state)

      if observed?
        raise_invalid("observed reading must carry a value") if value.nil?
        raise_invalid("observed value must be BigDecimal, got #{value.class}") unless value.is_a?(BigDecimal)
        raise_invalid("observed reading must carry a unit") if unit.nil?
      else
        raise_invalid("#{quality_state} reading must not carry a value (STAT-002)") unless value.nil?
        raise_invalid("#{quality_state} reading must not carry a unit") unless unit.nil?
      end

      self
    end

    # Stable field-ordered serialisation. This — not #inspect and not the Ruby
    # object graph — is what "byte-identical for the same seed" is measured
    # against.
    def canonical
      [
        sequence,
        subject_key,
        semantic_key,
        semantic_version,
        value.nil? ? "" : value.to_s("F"),
        unit,
        observed_at.utc.iso8601,
        local_date.iso8601,
        timezone_offset_minutes,
        quality_state,
        Serialization.canonical_hash(quality_flags),
        source_key,
        source_type,
        device_key,
        recording_method,
        measurement_protocol,
        group_key,
        source_record_id,
        slot,
        phase
      ].join("")
    end

    private

    def raise_invalid(message)
      raise ArgumentError, "invalid Reading (#{semantic_key} @ #{observed_at}): #{message}"
    end
  end

  module Serialization
    module_function

    def canonical(readings)
      readings.map(&:canonical).join("")
    end

    def digest(readings)
      Digest::SHA256.hexdigest(canonical(readings))
    end

    def canonical_hash(hash)
      return "" if hash.nil? || hash.empty?

      hash.map { |key, value| "#{key}=#{value}" }.sort.join(",")
    end
  end
end
