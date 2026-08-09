# frozen_string_literal: true

module Hypertension
  # Window arithmetic for the hypertension monitor pack.
  #
  # The arithmetic itself moved to `Telemetry::Windows` when the baseline
  # machinery in epic 003 needed the same half-open, day-aligned windows:
  # nothing in it is disease-shaped, and two copies would eventually disagree
  # about a boundary reading in a way that surfaces as an unexplainable bias
  # rather than as a failure.
  #
  # This shim remains so the monitors keep calling the helpers as private
  # instance methods, which is how they read.
  module MonitorWindows
    private

    def day_aligned_window_ending(...) = Telemetry::Windows.day_aligned_window_ending(...)
    def readings_in(...) = Telemetry::Windows.readings_in(...)
    def observed_readings(...) = Telemetry::Windows.observed_readings(...)
    def distinct_days(...) = Telemetry::Windows.distinct_days(...)
  end
end
