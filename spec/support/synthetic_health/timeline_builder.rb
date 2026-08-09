# frozen_string_literal: true

require_relative "decimal"
require_relative "measurement_schedule"
require_relative "missingness_pattern"
require_relative "quality_states"
require_relative "randomness"
require_relative "reading"
require_relative "source_plan"
require_relative "value_process"

module SyntheticHealth
  # Turns a subject, a window, a protocol and a set of value processes into
  # plain Readings.
  #
  # The generation order is deliberate and is what the harness's ground-truth
  # claims rest on:
  #
  #   1. enumerate every measurement opportunity in the window;
  #   2. generate the full latent series for each dimension — for EVERY
  #      opportunity, including ones that will end up missing;
  #   3. decide observation status per opportunity;
  #   4. apply instrumentation (calibration bias, device noise) to the ones
  #      that were observed;
  #   5. emit exactly one Reading per opportunity per dimension.
  #
  # Because step 2 happens before step 3, the biology is independent of the
  # missingness pattern: "the subject's blood pressure did not change, they
  # just stopped measuring" is a statement the harness can make structurally
  # rather than by hoping. And because step 4 happens after step 2, "the
  # numbers moved but the subject did not" is equally structural.
  #
  # Step 5 has no exceptions. An unexpected day, a dead device, a garbage
  # value — all of them produce a Reading carrying a state from the SC §12
  # taxonomy. Nothing is ever silently dropped and nothing is ever zeroed
  # (STAT-002).
  class TimelineBuilder
    attr_reader :subject, :window, :schedule, :dimensions, :source_plan, :streams

    def initialize(subject:,
                   window:,
                   schedule:,
                   dimensions:,
                   processes:,
                   source_plan:,
                   missingness:,
                   streams:)
      @subject = subject
      @window = window
      @schedule = schedule
      @dimensions = dimensions
      @processes = processes
      @source_plan = source_plan
      @missingness = missingness
      @streams = streams

      missing_processes = dimensions.map(&:semantic_key) - processes.keys
      unless missing_processes.empty?
        raise ArgumentError, "no value process supplied for #{missing_processes.join(', ')}"
      end
    end

    def opportunities
      @opportunities ||= @schedule.opportunities(window: @window, subject: @subject)
    end

    # { semantic_key => Array<BigDecimal> } — the underlying process, before
    # instrumentation and before anything went missing. Exposed because it is
    # the cleanest possible statement of what a scenario actually did.
    def latent_series
      @latent_series ||= @dimensions.to_h do |dimension|
        context = ValueProcess::Context.new(
          opportunities: opportunities,
          streams: @streams,
          label_prefix: dimension.semantic_key,
          window: @window
        )
        [ dimension.semantic_key, @processes.fetch(dimension.semantic_key).series(context) ]
      end
    end

    # Quality state per opportunity per dimension, resolved before any value
    # is recorded.
    def quality_states
      @quality_states ||= begin
        shared = !@missingness.is_a?(Hash)

        @dimensions.to_h do |dimension|
          pattern = shared ? @missingness : @missingness.fetch(dimension.semantic_key, MissingnessPattern.none)
          stream_label = shared ? "missingness" : "missingness|#{dimension.semantic_key}"
          rng = @streams.for(stream_label)

          states = opportunities.map do |opportunity|
            # The pattern is consulted even for opportunities the protocol
            # never expected, so its stream position does not depend on the
            # calendar. The answer is then overridden: a day with no expected
            # measurement is `not_expected`, which is not a gap at all.
            drawn = pattern.state_for(opportunity: opportunity, rng: rng)
            opportunity.expected? ? drawn : QualityStates::NOT_EXPECTED
          end

          [ dimension.semantic_key, states ]
        end
      end
    end

    def readings
      @readings ||= build_readings.freeze
    end

    def readings_for(semantic_key)
      readings.select { |reading| reading.semantic_key == semantic_key }
    end

    private

    # Shared across dimensions recorded at the same opportunity: one cuff
    # inflation yielding systolic, diastolic and pulse is ONE measurement
    # event and therefore one analytical unit, not three (SC §5, STAT-005).
    def group_key(opportunity)
      format("grp_%s_%05d", @subject.key, opportunity.index)
    end

    def build_readings
      sequence = -1

      opportunities.flat_map do |opportunity|
        source = @source_plan.source_for(opportunity)

        @dimensions.map do |dimension|
          sequence += 1
          build_reading(opportunity: opportunity, dimension: dimension, source: source, sequence: sequence)
        end
      end
    end

    def build_reading(opportunity:, dimension:, source:, sequence:)
      state = quality_states.fetch(dimension.semantic_key)[opportunity.index]
      observed = QualityStates.observed?(state)
      value = observed ? recorded_value(opportunity, dimension, source) : nil

      Reading.new(
        sequence: sequence,
        subject_key: @subject.key,
        semantic_key: dimension.semantic_key,
        semantic_version: dimension.semantic_version,
        value: value,
        unit: observed ? dimension.unit : nil,
        observed_at: opportunity.observed_at,
        local_date: opportunity.local_date,
        timezone_offset_minutes: @subject.utc_offset_minutes,
        quality_state: state,
        quality_flags: quality_flags_for(state),
        source_key: source.key,
        source_type: source.source_type,
        device_key: source.device_key,
        recording_method: source.recording_method,
        measurement_protocol: source.measurement_protocol,
        group_key: group_key(opportunity),
        source_record_id: source_record_id(opportunity, dimension),
        slot: opportunity.slot,
        phase: opportunity.phase
      ).validate!
    end

    # Latent biology + instrument bias + instrument noise, rounded to the
    # precision the instrument actually reports at.
    def recorded_value(opportunity, dimension, source)
      latent = latent_series.fetch(dimension.semantic_key)[opportunity.index]
      offset = source.offset_for(dimension.semantic_key)
      extra_noise = source.extra_noise_for(dimension.semantic_key)

      value = latent + offset
      unless extra_noise.zero?
        rng = @streams.for("source_noise|#{dimension.semantic_key}|#{source.key}")
        value += Deviates.noise(rng, extra_noise)
      end

      dimension.round(value)
    end

    def quality_flags_for(state)
      case state
      when QualityStates::INVALID_MEASUREMENT then { "reason" => "synthetic_invalid_measurement" }
      else {}
      end
    end

    # Stable and unique per (subject, dimension, instant): lets an engine spec
    # persist the same timeline twice and assert idempotency rather than
    # duplication.
    def source_record_id(opportunity, dimension)
      "#{@subject.key}|#{dimension.semantic_key}|#{opportunity.observed_at.utc.iso8601}"
    end
  end
end
