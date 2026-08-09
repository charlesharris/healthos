# frozen_string_literal: true

module Analysis
  # SC §21's maturity rule, and nothing else.
  #
  #   below minimum          → immature
  #   minimum <= units < target → partial
  #   target met             → mature
  #
  # Both units AND span must clear a level, because ten readings crammed into
  # three days is not a fortnight's baseline — SC §21 stores both for exactly
  # that reason, and taking the weaker of the two is what stops a burst of
  # measurement passing for sustained history.
  #
  # The numbers come from governed config (STAT-044), never from here.
  module BaselineMaturity
    module_function

    def call(usable_units:, calendar_span_days:, config: StatisticalConfig.instance)
      min_units = config.baseline("minimum_usable_units")
      min_span = config.baseline("minimum_calendar_span_days")
      target_units = config.baseline("target_usable_units")
      target_span = config.baseline("target_calendar_span_days")

      return "immature" if usable_units < min_units || calendar_span_days < min_span
      return "mature" if usable_units >= target_units && calendar_span_days >= target_span

      "partial"
    end

    # SC §23's affected-window minimum. Separate from baseline maturity: an
    # affected window is not a baseline and does not have maturity — it either
    # clears the minimum or the comparison is refused for insufficient
    # longitudinal evidence (STAT-018).
    def affected_window_sufficient?(usable_units:, calendar_span_days:,
                                    config: StatisticalConfig.instance)
      usable_units >= config.affected_window("minimum_usable_units") &&
        calendar_span_days >= config.affected_window("minimum_calendar_span_days")
    end
  end
end
