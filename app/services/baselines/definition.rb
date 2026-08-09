# frozen_string_literal: true

module Baselines
  # Base class for versioned BaselineDefinitions (HO §56, SC §19–22).
  #
  # SC §20 is blunt about why this class exists: **there is no universal
  # `normal`.** A baseline is a stated, defensible answer to "what counts as
  # this subject's usual", and different answers are legitimately different —
  # the last four weeks, the same phase of a previous cycle, the period before
  # an intervention, a matched cohort. Each is a definition with a key, a
  # version and a digest, so a Comparison can say which question it asked.
  #
  # What a definition does NOT do: judge whether the baseline is good enough
  # to support a claim. It reports `maturity`, `completeness`, `usable_units`
  # and `calendar_span_days`, and the evidence gate in 003-12..15 decides what
  # those permit. Keeping the two apart is what stops a gate hiding inside a
  # materializer, where nobody reviews it.
  class Definition
    # SC §20's list, in full. Only `personal_recent` is implemented; the rest
    # are named so that adding one is visibly adding a member of a known set
    # rather than inventing a category.
    BASELINE_TYPES = %w[
      personal_recent personal_historical phase_matched cycle_matched
      expected_trajectory cohort_prior matched_cohort pre_intervention
    ].freeze

    DEFINITIONS = {
      "personal_recent" => "Baselines::PersonalRecent"
    }.freeze

    # Everything a Comparison needs to reason about this baseline, and nothing
    # it needs to recompute. STAT-021: the denominators travel with the value.
    Result = Struct.new(
      :definition, :window, :as_of,
      :central_value, :dispersion, :unit,
      :usable_units, :raw_reading_count, :calendar_span_days,
      :completeness, :maturity, :missing_by_state, :source_summary,
      :inputs, :daily_values,
      keyword_init: true
    ) do
      def mature? = maturity == "mature"
      def immature? = maturity == "immature"

      # Never a bare ratio. SC §14: 70% of ten days and 70% of a hundred are
      # not the same evidence.
      def summary
        { usable_units: usable_units, calendar_span_days: calendar_span_days,
          completeness: completeness, maturity: maturity }
      end
    end

    class << self
      def key = raise(NotImplementedError, "#{name} must define .key")
      def version = raise(NotImplementedError, "#{name} must define .version")

      def baseline_type
        raise(NotImplementedError, "#{name} must define .baseline_type")
      end

      # HO §56's sufficiency fields. Defaulted from governed configuration
      # (STAT-044) rather than written here, so the Statistical Contract's
      # numbers live in exactly one file. A domain pack that knows a
      # clinically meaningful cadence overrides these — SC §22 explicitly
      # calls the generic values "engineering defaults only".
      def minimum_usable_units = config.baseline("minimum_usable_units")
      def target_usable_units = config.baseline("target_usable_units")
      def minimum_calendar_span_days = config.baseline("minimum_calendar_span_days")
      def target_calendar_span_days = config.baseline("target_calendar_span_days")

      # SC §19. How far back this definition may reach at all. Distinct from
      # the window: a definition that would happily search a year to find ten
      # days is not describing "recent", whatever it names itself.
      def eligible_lookback_days = target_calendar_span_days

      # HO §56 exclusions. Quality states that do not contribute a usable
      # unit. They are still reported in `missing_by_state` — STAT-002 forbids
      # imputing them, and dropping them from the record entirely would hide
      # that we looked.
      def excluded_quality_states = Observation::QUALITY_STATES - %w[observed]

      # HO §56 aggregation rules. Named rather than implicit: SC §22 requires
      # a day's readings to collapse to one value before summarising, or one
      # enthusiastic afternoon outvotes a fortnight (STAT-005).
      def aggregation = "daily_median"

      # HO §56 source compatibility. What the baseline was measured WITH
      # travels with it, so a Comparison can apply STAT-008/009 rather than
      # rating an instrument change as biology.
      def source_compatibility = "report_mix"

      # Digested, so a behaviour change without a version bump is detectable
      # (HO §25). The thresholds are in here deliberately: they decide what
      # the baseline IS, and a definition that quietly started accepting five
      # days instead of ten would otherwise keep its identity.
      def parameters
        {
          "baseline_type" => baseline_type,
          "aggregation" => aggregation,
          "source_compatibility" => source_compatibility,
          "eligible_lookback_days" => eligible_lookback_days,
          "excluded_quality_states" => excluded_quality_states,
          "minimum_usable_units" => minimum_usable_units,
          "target_usable_units" => target_usable_units,
          "minimum_calendar_span_days" => minimum_calendar_span_days,
          "target_calendar_span_days" => target_calendar_span_days
        }
      end

      def digest
        Definitions::DefinitionDigest.compute(key: key, version: version, parameters: parameters)
      end

      def find(definition_key)
        name = DEFINITIONS[definition_key.to_s]
        raise ArgumentError, "no baseline definition for #{definition_key.inspect}" if name.blank?

        name.constantize
      end

      def config = Analysis::StatisticalConfig.instance
    end

    def initialize(subject:, semantic_key:, as_of:, ends_at: nil)
      @subject = subject
      @semantic_key = semantic_key
      @as_of = as_of
      # Where the baseline stops. Normally the start of the affected window,
      # so the two abut without overlapping.
      @ends_at = ends_at || as_of
    end

    attr_reader :subject, :semantic_key, :as_of, :ends_at

    def build = raise(NotImplementedError)
  end
end
