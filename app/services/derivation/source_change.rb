# frozen_string_literal: true

module Derivation
  # source_changed / recording_method_changed as derived signals (HO §29).
  #
  # Boolean-valued dimensions, so they can be compared, monitored and
  # surfaced like any other evidence — HO §29: "these are first-class
  # evidence. They are not merely data-quality annotations." The continuous
  # proportion lives on SourceProfile; this is the dimension a monitor can
  # watch.
  class SourceChange < Algorithm
    KEY = "measurement_source_changed"
    VERSION = 1

    def self.key = KEY
    def self.version = VERSION

    def initialize(subject:, semantic_key:, affected_window:, baseline_window:)
      @subject = subject
      @semantic_key = semantic_key
      @affected_window = affected_window
      @baseline_window = baseline_window
    end

    def call
      affected = Measurement::SourceProfile.for_window(
        subject: @subject, semantic_key: @semantic_key, window: @affected_window
      )
      baseline = Measurement::SourceProfile.for_window(
        subject: @subject, semantic_key: @semantic_key, window: @baseline_window
      )

      comparison = Measurement::SourceProfile.compare(affected: affected, baseline: baseline)

      if comparison.indeterminate?
        return Outcome.new(value_numeric: nil, value_json: nil, unit: nil, inputs: [],
                           usable_input_count: 0, raw_input_count: 0,
                           status: "insufficient_input")
      end

      Outcome.new(
        value_numeric: nil,
        value_json: {
          "changed" => comparison.changed_share.positive?,
          # The proportion travels with the boolean, because SC §11's
          # thresholds are proportions and a bare true/false cannot feed them.
          "changed_share" => comparison.changed_share,
          "affected_sources" => affected.source_mix.size,
          "baseline_sources" => baseline.source_mix.size,
          "affected_methods" => affected.method_mix.keys.sort,
          "baseline_methods" => baseline.method_mix.keys.sort,
          "method_changed" => affected.method_mix.keys.sort != baseline.method_mix.keys.sort
        },
        unit: nil, inputs: [],
        usable_input_count: affected.total, raw_input_count: affected.total + baseline.total,
        status: "computed"
      )
    end
  end
end
