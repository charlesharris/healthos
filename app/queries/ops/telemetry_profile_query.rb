# frozen_string_literal: true

module Ops
  # Descriptive telemetry for the exploratory surfaces: what readings look
  # like over a window, and how a selected region differs from everything
  # outside it.
  #
  # Serves both Quick Review (focused on one subject, selection defaulting to
  # the Signal's own window) and Explore (no focus subject, selection dragged
  # by the operator). One object, because two would drift and then disagree
  # about what "baseline" means.
  #
  # DELIBERATELY NOT NAMED Comparison OR Difference. Those are immutable,
  # versioned, digested analytical artifacts built by Epic 003 and pinned into
  # saved Investigations (STAT-040/041). This is a live read for a screen: not
  # persisted, not versioned, and never to be cited as one of them.
  #
  #   May     — counts, shares, denominators, medians, coverage. Descriptive
  #             statements about what is in the database.
  #   May not — that a difference is significant, strong, or caused by
  #             anything. Evidence strength is an artifact's job.
  #
  # Ordering of the dimension profiles is fixed by contract precedence, not by
  # effect size (STAT-019/024, STAT-035): coverage first because every other
  # number is read through it, then measurement behaviour, then identity, then
  # biology. A "most different first" sort — the obvious thing to write —
  # would rank a large biological shift above the source change that explains
  # it, which is the inversion STAT-035 exists to prevent.
  class TelemetryProfileQuery < Tenanted::Query
    # The whole span the chart draws. Fixed: dragging moves what is selected
    # inside it, never what is on screen, so two selections over the same Case
    # stay comparable.
    Window = Struct.new(:from, :to, keyword_init: true) do
      def days = (to.to_date - from.to_date).to_i
    end

    # What the operator (or the Signal) has picked out.
    #
    # `value_min`/`value_max` make it a box rather than a time range, which is
    # how BubbleUp works. It is also selection on the outcome variable, so the
    # UI says so — see #conditioned_on_value?.
    Selection = Struct.new(:from, :to, :value_min, :value_max, :origin, keyword_init: true) do
      def days = (to.to_date - from.to_date).to_i
      def value_bounded? = value_min.present? && value_max.present?

      def cover?(at, value = nil)
        return false unless at >= from && at < to
        return true unless value_bounded?

        value.present? && value >= value_min && value <= value_max
      end

      def from_signal? = origin == :signal

      # Explore opens with nothing selected: the operator has not asked a
      # question yet, and pre-selecting a region would answer one they did not
      # ask.
      def none? = origin == :none

      # A dragged region arrives as query parameters, so it is untrusted in
      # both senses: it may be malformed, and it may point outside the chart.
      # Clamped rather than rejected — a selection that runs a day past the
      # edge is a fat finger, not an attack, and silently dropping it would
      # leave the operator staring at an unchanged screen.
      def clamp_to(range)
        low = [ [ from, range.from ].max, range.to ].min
        high = [ [ to, range.to ].min, range.from ].max
        return nil if high <= low

        self.class.new(from: low, to: high, value_min: value_min, value_max: value_max,
                       origin: :custom)
      end

      def self.from_params(params)
        from = parse_time(params[:from])
        to = parse_time(params[:to])
        return nil if from.nil? || to.nil? || to <= from

        low = parse_number(params[:vmin])
        high = parse_number(params[:vmax])
        low, high = [ low, high ].minmax if low && high

        new(from: from, to: to, value_min: low, value_max: high, origin: :custom)
      end

      def self.parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def self.parse_number(value)
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def to_params
        { from: from.iso8601, to: to.iso8601,
          vmin: value_bounded? ? value_min : nil, vmax: value_bounded? ? value_max : nil }.compact
      end
    end

    Reading = Struct.new(:at, :value, :recording_method, :quality_state, keyword_init: true)
    Cell = Struct.new(:day_index, :band_index, :count, keyword_init: true)

    Profile = Struct.new(:key, :label, :kind, :note, :rows, :baseline_total, :selection_total,
                         :unit_label, :truncated_from, keyword_init: true) do
      # One value present on both sides: nothing moved. Reported as a sentence
      # rather than two full-width bars — and still reported, because "the
      # instrumentation did not change" is an answer, and dropping the card
      # would make it indistinguishable from "not examined".
      def unchanged?
        rows.length == 1 && baseline_total.positive? && selection_total.positive?
      end
    end

    ProfileRow = Struct.new(:label, :baseline_count, :selection_count,
                            :baseline_share, :selection_share, :handle, keyword_init: true)

    Stat = Struct.new(:label, :baseline, :selection, :note, keyword_init: true)

    DEFAULT_BASELINE_DAYS = 21
    BAND_TARGET = 10

    # A dimension with dozens of values is a table, not a chart. The remainder
    # is folded into one row and the fold is stated on the card — a silent
    # top-N reads as "these are all of them".
    MAX_ROWS = 8

    def initialize(organization:, range:, selection:, subject: nil, semantic_key: nil,
                   preferred_keys: [], membership: nil)
      super(organization: organization, membership: membership)

      @subject = subject
      @range = range
      @selection = selection
      @requested_key = semantic_key
      @preferred_keys = Array(preferred_keys)
    end

    attr_reader :subject, :range, :selection

    def focused? = subject.present?

    # True when the operator dragged a box that narrows the value axis. The
    # dimension strip then carries a warning, because selecting on the outcome
    # and reporting which dimensions differ is a hypothesis generator, not a
    # finding — the differences may exist *because* of the selection.
    def conditioned_on_value? = selection.value_bounded?

    def available_keys
      @available_keys ||= begin
        counts = scoped_observations.group(:semantic_key).count

        counts.keys.sort_by do |key|
          preference = @preferred_keys.index(key)
          [ preference.nil? ? 1 : 0, preference || 0, -counts[key], key ]
        end
      end
    end

    def semantic_key
      @semantic_key ||=
        if @requested_key.present? && available_keys.include?(@requested_key)
          @requested_key
        else
          available_keys.first
        end
    end

    def unit
      @unit ||= keyed(scoped_observations).where.not(unit: nil).limit(1).pick(:unit)
    end

    def resolve = self

    def any_data? = semantic_key.present? && cohort_cells.any?

    def days
      @days ||= (range.from.to_date...range.to.to_date).to_a
    end

    # ---- The focus subject's own readings ---------------------------------
    #
    # Empty on Explore, which has no focus subject: the density layer is the
    # whole story there.
    def readings
      @readings ||=
        if focused?
          keyed(subject_observations).order(:observed_at)
            .pluck(:observed_at, :value_numeric, :recording_method, :quality_state)
            .map { |at, value, method, state| Reading.new(at: at, value: value&.to_f, recording_method: method, quality_state: state) }
        else
          []
        end
    end

    # STAT-002: this is not zero and must not render as zero. A day with no
    # measurement and a day with a measurement of 0 are different facts, and
    # only one of them is possible for a blood pressure.
    def days_without_readings
      return [] unless focused?

      @days_without_readings ||= days - readings.map { |reading| reading.at.to_date }
    end

    def selection_readings = readings.select { |r| selection.cover?(r.at, r.value) }
    def baseline_readings = readings.reject { |r| selection.cover?(r.at, r.value) }

    # ---- Density ----------------------------------------------------------
    #
    # The whole organization on these axes. A single subject measuring once a
    # day cannot fill a heatmap — 21 cells of exactly 1 is a scatter plot
    # wearing a heatmap's clothes. On Quick Review this is CONTEXT ONLY: the
    # monitor that raised the Case looked at one subject, and a between-subject
    # position is not the evidence for it (STAT-021).
    def cohort_cells
      @cohort_cells ||= begin
        counts = Hash.new(0)
        cohort_rows.each do |observed_at, value|
          day_index = days.index(observed_at.to_date)
          band_index = band_index_for(value.to_f)
          next if day_index.nil? || band_index.nil?

          counts[[ day_index, band_index ]] += 1
        end
        counts.map { |(day, band), count| Cell.new(day_index: day, band_index: band, count: count) }
      end
    end

    def cohort_subject_count
      @cohort_subject_count ||= keyed(cohort_observations).distinct.count(:subject_id)
    end

    def value_bands
      @value_bands ||= begin
        values = cohort_rows.filter_map { |_, value| value&.to_f } + readings.filter_map(&:value)
        if values.empty?
          []
        else
          low = (values.min / BAND_TARGET).floor * BAND_TARGET
          high = (values.max / BAND_TARGET).ceil * BAND_TARGET
          high += BAND_TARGET if high == low
          (low...high).step(BAND_TARGET).to_a
        end
      end
    end

    def band_index_for(value)
      return nil if value_bands.empty?

      index = ((value - value_bands.first) / BAND_TARGET).floor
      index.between?(0, value_bands.length - 1) ? index : nil
    end

    def band_size = BAND_TARGET
    def max_cell_count = cohort_cells.map(&:count).max.to_i

    # ---- "What was different?" --------------------------------------------

    def profiles
      @profiles ||= [
        dimension_profile(:recording_method, "Recording method", :measurement,
                          "How the reading was taken. A change here can look exactly like a change in the subject (STAT-003)."),
        dimension_profile(:quality_state, "Quality state", :measurement,
                          "The missingness taxonomy, never a boolean (STAT-010)."),
        source_profile,
        (subject_dimension_profile unless focused?)
      ].compact
    end

    # Coverage and cadence — the denominators. Before any share, and never a
    # share themselves.
    def coverage_stats
      # A time-only selection owns its days outright, so the baseline has the
      # rest. A VALUE-BOUNDED selection does not: a day inside the selection's
      # time range still contributes baseline readings for values outside the
      # box, so both sides can see the same day. Subtracting anyway produced
      # "21/20" — a numerator above its own denominator, which is worse than
      # no denominator at all.
      baseline_days =
        if selection.value_bounded? || selection.none?
          range.days
        else
          [ range.days - selection.days, 0 ].max
        end

      [
        Stat.new(label: "Days with a reading",
                 baseline: "#{covered_days(baseline_readings_scope)}/#{baseline_days}",
                 selection: "#{covered_days(selection_readings_scope)}/#{selection.days}",
                 note: "Days that produced a reading, out of days in the window."),
        Stat.new(label: "Measurement events",
                 baseline: baseline_readings_scope.distinct.count(:observation_group_id),
                 selection: selection_readings_scope.distinct.count(:observation_group_id),
                 note: "Readings taken together are one event, not several (STAT-004/005)."),
        Stat.new(label: "Readings",
                 baseline: baseline_readings_scope.count,
                 selection: selection_readings_scope.count,
                 note: "Raw rows. Repeated readings are not independent n (STAT-021).")
      ]
    end

    # Biological summary, last and explicitly caveated (STAT-035). Median
    # rather than mean because one mistyped reading should not move it.
    def value_summary
      base = baseline_readings_scope.where.not(value_numeric: nil).pluck(:value_numeric).map(&:to_f)
      sel = selection_readings_scope.where.not(value_numeric: nil).pluck(:value_numeric).map(&:to_f)
      return nil if base.empty? || sel.empty?

      Stat.new(label: "Median #{semantic_key.split('.').last.tr('_', ' ')}",
               baseline: format_value(median(base)), selection: format_value(median(sel)),
               note: "Descriptive only. A difference here is not a Finding and carries no evidence strength.")
    end

    private

    # Rows the dimension strip is computed over: one subject on Quick Review,
    # the whole organization on Explore.
    def profile_scope = keyed(focused? ? subject_observations : cohort_observations)

    # Ordinary Active Record predicates, deliberately.
    #
    # The first version built a `COUNT(*) FILTER (WHERE …)` string and
    # interpolated it, sanitized, into a pluck. It was safe and Brakeman
    # flagged it anyway — correctly, in the sense that a reviewer cannot tell
    # at the call site whether the interpolated fragment was sanitized. The
    # value bounds arrive from a query parameter, so this is exactly the place
    # not to make a reviewer take that on trust. Two grouped counts and a
    # merge cost one extra query per dimension and carry no raw SQL at all.
    def selection_readings_scope
      scope = profile_scope.where(observed_at: selection.from...selection.to)
      return scope unless selection.value_bounded?

      scope.where(value_numeric: selection.value_min..selection.value_max)
    end

    def baseline_readings_scope
      profile_scope.where.not(id: selection_readings_scope.select(:id))
    end

    def covered_days(scope)
      scope.distinct.count(Arel.sql("date(observed_at)"))
    end

    # Counts on both sides of the selection, keyed the same way, merged into
    # the tuple shape build_profile expects.
    def split_counts(grouping)
      selected = selection_readings_scope.group(grouping).count
      baseline = baseline_readings_scope.group(grouping).count

      (selected.keys | baseline.keys).map do |value|
        [ value, baseline.fetch(value, 0), selected.fetch(value, 0) ]
      end
    end

    def scoped_observations = focused? ? subject_observations : cohort_observations

    def subject_observations
      for_tenant(Observation.all)
        .where(subject_id: subject.id)
        .where(observed_at: range.from...range.to)
        .where(quality_state: "observed")
    end

    def cohort_observations
      for_tenant(Observation.all)
        .where(observed_at: range.from...range.to)
        .where(quality_state: "observed")
    end

    def keyed(relation) = semantic_key.present? ? relation.where(semantic_key: semantic_key) : relation

    def cohort_rows
      @cohort_rows ||= keyed(cohort_observations).pluck(:observed_at, :value_numeric)
    end

    def dimension_profile(column, label, kind, note)
      tuples = split_counts(column).map do |value, base, sel|
        [ value.to_s.presence || "unrecorded", base, sel, nil ]
      end

      build_profile(tuples, column, label, kind, note)
    end

    def source_profile
      tuples = split_counts_on(:source, "sources.key").map { |value, base, sel| [ value.to_s, base, sel, nil ] }

      build_profile(tuples, :source, "Source", :measurement,
                    "Which system the reading arrived from. A source change above 30% caps biological evidence at WEAK (STAT-008).")
    end

    # Same split as #split_counts, over a joined column.
    def split_counts_on(association, grouping)
      selected = selection_readings_scope.joins(association).group(grouping).count
      baseline = baseline_readings_scope.joins(association).group(grouping).count

      (selected.keys | baseline.keys).map do |value|
        [ value, baseline.fetch(value, 0), selected.fetch(value, 0) ]
      end
    end

    # Explore only. "Which subjects are in this region" is the question a
    # cohort heatmap exists to answer — and the handle stays opaque, because
    # identity is PHI and requires a deliberate, audited read (HO §92).
    def subject_dimension_profile
      tuples = split_counts_on(:subject, "subjects.public_id")
        .map { |handle, base, sel| [ handle, base, sel, handle ] }

      build_profile(tuples, :subject, "Subject", :identity,
                    "Who the readings came from. Descriptive: an over-represented subject is a place to look, not a finding.")
    end

    def build_profile(tuples, key, label, kind, note)
      return nil if tuples.empty?

      baseline_total = tuples.sum { |(_, base, _, _)| base }
      selection_total = tuples.sum { |(_, _, sel, _)| sel }
      return nil if baseline_total.zero? && selection_total.zero?

      # Ordered by presence in the SELECTION, because that is the region the
      # operator asked about. This is presentation order within one dimension,
      # not a ranking across dimensions — STAT-019's rule governs the latter.
      ordered = tuples.sort_by { |(value, base, sel, _)| [ -sel, -base, value.to_s ] }
      kept, folded = ordered.take(MAX_ROWS), ordered.drop(MAX_ROWS)

      rows = kept.map do |value, base, sel, handle|
        # Underscores are separators in an enum value (`device_automatic`) and
        # load-bearing in an opaque handle (`sub_90rd…`). Humanizing the second
        # corrupts an identifier the operator is meant to be able to copy.
        ProfileRow.new(label: handle.presence || value.to_s.tr("_", " "), handle: handle,
                       baseline_count: base, selection_count: sel,
                       baseline_share: share(base, baseline_total),
                       selection_share: share(sel, selection_total))
      end

      if folded.any?
        rows << ProfileRow.new(
          label: "other (#{folded.length})",
          baseline_count: folded.sum { |(_, base, _, _)| base },
          selection_count: folded.sum { |(_, _, sel, _)| sel },
          baseline_share: share(folded.sum { |(_, base, _, _)| base }, baseline_total),
          selection_share: share(folded.sum { |(_, _, sel, _)| sel }, selection_total)
        )
      end

      Profile.new(key: key, label: label, kind: kind, note: note, rows: rows,
                  baseline_total: baseline_total, selection_total: selection_total,
                  unit_label: "readings",
                  truncated_from: folded.any? ? ordered.length : nil)
    end

    def share(count, total) = total.zero? ? nil : (count.to_f / total)

    def median(values)
      sorted = values.sort
      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    def format_value(value)
      formatted = value.round(1)
      formatted = formatted.to_i if (formatted % 1).zero?
      unit.present? ? "#{formatted} #{unit}" : formatted.to_s
    end
  end
end
