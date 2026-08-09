# frozen_string_literal: true

module Hypertension
  # Reference correlation rules (HO §42). Domain-pack data, never platform
  # core (S2C-025, INV-35): correlation windows, case types and compatibility
  # are all disease-shaped decisions.
  #
  # ⚠️ Correlation windows are NON-CLINICAL fixtures (HO §175).
  module CorrelationRules
    CASE_TYPES = {
      "blood_pressure_change" => {
        signal_types: %w[threshold_excursion blood_pressure_trajectory_change variability_change],
        # How close in time two Signals must be to describe the same episode.
        correlation_window: 14.days,
        # How long after resolution a related Signal reopens rather than
        # starting fresh (S2C-017).
        reopen_horizon: 7.days,
        title: "Blood pressure pattern change"
      },
      "monitoring_interruption" => {
        signal_types: %w[measurement_frequency_change source_change data_quality_change],
        correlation_window: 21.days,
        reopen_horizon: 14.days,
        title: "Monitoring interrupted"
      },
      "care_gap" => {
        signal_types: %w[workflow_event],
        correlation_window: 30.days,
        reopen_horizon: 14.days,
        title: "Care gap"
      }
    }.freeze

    # Signals that may attach CONTEXTUALLY to a blood_pressure_change Case
    # rather than opening their own (HO §42: "source/measurement Signals may
    # attach contextually when they help explain the same operational work").
    #
    # This is the mechanism behind STAT-007's instrumentation-before-biology
    # ordering: the fact that the cuff changed belongs on the same Case as the
    # apparent BP shift, because it may be the explanation for it.
    CONTEXTUAL_ATTACHMENTS = {
      "blood_pressure_change" => %w[source_change measurement_frequency_change data_quality_change]
    }.freeze

    module_function

    def domain_key = "hypertension"

    def case_type_for(signal_type)
      CASE_TYPES.find { |_type, config| config[:signal_types].include?(signal_type) }&.first
    end

    def config_for(case_type) = CASE_TYPES.fetch(case_type)

    def contextual_for?(case_type, signal_type)
      Array(CONTEXTUAL_ATTACHMENTS[case_type]).include?(signal_type)
    end

    # A Signal is compatible with a Case when it is the same kind of work, or
    # when it contextually explains that work. HO §42: "keep Cases separate
    # when routing/action differs materially" — which is why a care_gap never
    # absorbs a blood_pressure_change.
    def compatible?(case_record, signal)
      return false unless case_record.domain_key == domain_key

      config = CASE_TYPES[case_record.case_type]
      return false if config.nil?

      primary = config[:signal_types].include?(signal.signal_type)
      contextual = contextual_for?(case_record.case_type, signal.signal_type)
      return false unless primary || contextual

      within_window?(case_record, signal, config[:correlation_window])
    end

    def relationship_for(case_record, signal)
      config = CASE_TYPES[case_record.case_type]
      config[:signal_types].include?(signal.signal_type) ? "supporting" : "contextual"
    end

    def within_window?(case_record, signal, window)
      anchor = case_record.last_signal_at || case_record.detected_at
      (signal.detected_at - anchor).abs <= window
    end

    def reopen_horizon_for(case_type)
      CASE_TYPES.dig(case_type, :reopen_horizon) || 0.seconds
    end
  end
end
