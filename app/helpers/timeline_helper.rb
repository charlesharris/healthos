# frozen_string_literal: true

# Presentation for the Case timeline (HO §90).
#
# The timeline is read-only over append-only sources and stays in one order,
# newest last. Nothing here reorders, hides or summarises away an operational
# entry — the folding applies only to runs of routine measurements, and a
# folded run states its own size and opens in place.
#
# The problem being solved is not verbosity for its own sake. On a Case with
# three weeks of daily readings the timeline was 63 measurement lines and 3
# workflow lines, so "what happened to this Case" — the question the timeline
# exists to answer — was invisible without scrolling past everything that
# merely *arrived*.
module TimelineHelper
  # Entries that describe human or system action on the Case, as opposed to
  # telemetry arriving. This split is what the filter is built on.
  WORKFLOW_KINDS = %w[case_event disposition workflow_action].freeze
  SIGNAL_KINDS = %w[signal].freeze
  READING_KINDS = %w[observation].freeze

  FILTERS = {
    "all" => { label: "Everything", kinds: nil },
    "workflow" => { label: "Workflow", kinds: WORKFLOW_KINDS },
    "signals" => { label: "Signals", kinds: SIGNAL_KINDS },
    "readings" => { label: "Readings", kinds: READING_KINDS }
  }.freeze

  DEFAULT_FILTER = "all"

  # Shorter than this and folding costs a click to save two lines.
  FOLD_THRESHOLD = 4

  # A folded run of consecutive measurements. Consecutive means nothing else
  # happened between them, so collapsing the run cannot hide an event.
  Run = Struct.new(:entries, keyword_init: true) do
    def length = entries.length
    def first_at = entries.first.at
    def last_at = entries.last.at
    def at = last_at
    def days = entries.map { |entry| entry.at.to_date }.uniq.length
  end

  def timeline_filter(requested)
    FILTERS.key?(requested.to_s) ? requested.to_s : DEFAULT_FILTER
  end

  def timeline_counts(entries)
    FILTERS.transform_values do |filter|
      filter[:kinds].nil? ? entries.length : entries.count { |entry| filter[:kinds].include?(entry.kind) }
    end
  end

  def filter_timeline(entries, filter)
    kinds = FILTERS.fetch(filter, FILTERS[DEFAULT_FILTER])[:kinds]
    return entries if kinds.nil?

    entries.select { |entry| kinds.include?(entry.kind) }
  end

  # Folds runs of consecutive readings and leaves everything else alone.
  #
  # Deliberately not applied when the reader has asked to see only readings:
  # they asked for the rows, so give them the rows.
  def fold_timeline(entries, filter)
    return entries if filter == "readings"

    entries
      .chunk_while { |a, b| a.kind == "observation" && b.kind == "observation" }
      .flat_map do |chunk|
        chunk.length >= FOLD_THRESHOLD && chunk.first.kind == "observation" ? [ Run.new(entries: chunk) ] : chunk
      end
  end

  def timeline_kind_label(kind)
    { "case_event" => "workflow", "workflow_action" => "action",
      "observation" => "measurement" }.fetch(kind, kind)
  end
end
