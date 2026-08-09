# frozen_string_literal: true

module Ops
  # Descriptive telemetry for Quick Review: what the readings look like across
  # the window a Signal is about, and how the measurement behaviour in that
  # window differs from the period before it.
  #
  # DELIBERATELY NOT NAMED Comparison OR Difference. Those are immutable,
  # versioned, digested analytical artifacts built by Epic 003 and pinned into
  # saved Investigations (STAT-040/041). This is a live read for a screen: it
  # is not persisted, not versioned, and must never be cited as one of them.
  # It computes nothing an artifact would compute — no evidence strength, no
  # completeness gates, no effect-magnitude class.
  #
  # What it therefore may and may not say:
  #
  #   May   — counts, shares, denominators, medians, coverage. Descriptive
  #           statements about what is in the database.
  #   May not — that a difference is significant, strong, or caused by
  #           anything. A Difference is descriptive, never causal, and
  #           evidence strength is an artifact's job, not a chart's.
  #
  # Ordering of the dimension profiles is fixed by contract precedence, not by
  # effect size (STAT-019/024, STAT-035): coverage first because every other
  # number is read through it, then measurement behaviour, then biology. A
  # "most different first" sort — the obvious thing to write — would rank a
  # large biological shift above a source change that explains it, which is
  # exactly the inversion STAT-035 exists to prevent.
  class TelemetryProfileQuery < Tenanted::Query
    # A reading is one row; a measurement event is one observation_group. They
    # are different denominators and STAT-004/005/021 requires both, because
    # systolic+diastolic+pulse recorded together is one measurement, not three
    # independent observations.
    Window = Struct.new(:from, :to, :label, keyword_init: true) do
      def days = ((to.to_date - from.to_date).to_i)
      def cover?(time) = time >= from && time < to
    end

    Reading = Struct.new(:at, :value, :recording_method, :quality_state, keyword_init: true)

    Cell = Struct.new(:day_index, :band_index, :count, keyword_init: true)

    Profile = Struct.new(:key, :label, :kind, :note, :rows, :baseline_total, :selection_total,
                         :unit_label, keyword_init: true) do
      # One value, present in both windows: nothing moved. Reported as a
      # sentence rather than two full-width bars — and still reported, because
      # "the instrumentation did not change" is an answer a reader needs, and
      # dropping the card would make it indistinguishable from "not examined".
      def unchanged?
        rows.length == 1 && baseline_total.positive? && selection_total.positive?
      end
    end

    ProfileRow = Struct.new(:label, :baseline_count, :selection_count,
                            :baseline_share, :selection_share, keyword_init: true)

    Stat = Struct.new(:label, :baseline, :selection, :note, keyword_init: true)

    DEFAULT_BASELINE_DAYS = 21

    # Bands are round numbers rather than data-fitted quantiles: a provider
    # reads "140–150" and knows what it means, and a band whose edges move
    # with the data cannot be compared between two Cases.
    BAND_TARGET = 10

    def initialize(organization:, subject:, selection:, baseline:,
                   semantic_key: nil, preferred_keys: [], membership: nil)
      super(organization: organization, membership: membership)

      @subject = subject
      @selection = selection
      @baseline = baseline
      @requested_key = semantic_key
      @preferred_keys = Array(preferred_keys)
    end

    attr_reader :subject, :selection, :baseline

    # Every observation key this subject actually has data for in the window,
    # so the switcher offers what exists rather than what the domain pack
    # hopes exists. Keeps the platform core domain-neutral (CLAUDE.md): no
    # blood-pressure key is named anywhere in this class.
    #
    # `preferred_keys` is the domain pack's own declared order, passed in
    # rather than looked up here. Without it the default fell out of an
    # alphabetical tie — three keys with 21 readings each — and landed on
    # diastolic for a Case whose Signal quotes systolic medians, so the chart
    # and the claim printed underneath it disagreed.
    def available_keys
      @available_keys ||= begin
        counts = window_observations.group(:semantic_key).count

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
      @unit ||= readings_relation.where.not(unit: nil).limit(1).pick(:unit)
    end

    def resolve = self

    def any_data? = semantic_key.present? && readings.any?

    # This subject's own readings, which are what the Case is about.
    def readings
      @readings ||= readings_relation
        .order(:observed_at)
        .pluck(:observed_at, :value_numeric, :recording_method, :quality_state)
        .map do |at, value, method, state|
          Reading.new(at: at, value: value&.to_f, recording_method: method, quality_state: state)
        end
    end

    def days
      @days ||= (baseline.from.to_date...selection.to.to_date).to_a
    end

    # Days on which this subject produced no reading at all.
    #
    # STAT-002: this is not zero and must not render as zero. A day with no
    # measurement and a day with a measurement of 0 are different facts, and
    # only one of them is possible for blood pressure.
    def days_without_readings
      @days_without_readings ||= days - readings.map { |reading| reading.at.to_date }
    end

    def value_bands
      @value_bands ||= begin
        values = cohort_values + readings.filter_map(&:value)
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

    # The density layer: how the whole program's readings are distributed over
    # the same axes.
    #
    # A single subject measuring once a day cannot fill a heatmap — 21 cells
    # of exactly 1 is a scatter plot wearing a heatmap's clothes. The program
    # cohort can, and "where does this subject sit in the program" is a real
    # question. It is CONTEXT ONLY and labelled as such: this Case was raised
    # by a within-subject monitor, and a between-subject position is not the
    # evidence for it (STAT-021 — readings across subjects are certainly not
    # independent observations of one thing).
    def cohort_cells
      @cohort_cells ||= begin
        counts = Hash.new(0)
        cohort_rows.each do |observed_at, value|
          day_index = days.index(observed_at.to_date)
          band_index = band_index_for(value.to_f)
          next if day_index.nil? || band_index.nil?

          counts[[ day_index, band_index ]] += 1
        end

        counts.map { |(day_index, band_index), count| Cell.new(day_index: day_index, band_index: band_index, count: count) }
      end
    end

    def cohort_subject_count
      @cohort_subject_count ||= cohort_relation.distinct.count(:subject_id)
    end

    def max_cell_count = cohort_cells.map(&:count).max.to_i

    def band_index_for(value)
      return nil if value_bands.empty?

      index = ((value - value_bands.first) / BAND_TARGET).floor
      index.between?(0, value_bands.length - 1) ? index : nil
    end

    def band_size = BAND_TARGET

    # ---- "What was different?" -------------------------------------------
    #
    # Fixed order, stated in one place. Coverage is first because a share
    # computed over four readings and a share computed over forty look
    # identical on a bar and mean entirely different things.
    def profiles
      @profiles ||= [
        recording_method_profile,
        quality_state_profile,
        source_profile
      ].compact
    end

    # Coverage and cadence — the denominators. Rendered before any share,
    # never as a share themselves.
    def coverage_stats
      [
        Stat.new(label: "Days with a reading",
                 baseline: coverage_for(baseline), selection: coverage_for(selection),
                 note: "Days covered out of days in the window."),
        Stat.new(label: "Measurement events",
                 baseline: events_in(baseline), selection: events_in(selection),
                 note: "Readings taken together are one event, not several (STAT-004/005)."),
        Stat.new(label: "Readings",
                 baseline: readings_in(baseline).count, selection: readings_in(selection).count,
                 note: "Raw rows. Repeated readings are not independent n (STAT-021).")
      ]
    end

    # Biological summary, last and explicitly caveated (STAT-035). Median
    # rather than mean because a single mistyped reading should not move it,
    # and no dispersion claim is made from counts this small.
    def value_summary
      base = readings_in(baseline).filter_map(&:value)
      sel = readings_in(selection).filter_map(&:value)
      return nil if base.empty? || sel.empty?

      Stat.new(label: "Median #{semantic_key.split('.').last.tr('_', ' ')}",
               baseline: format_value(median(base)), selection: format_value(median(sel)),
               note: "Descriptive only. A difference here is not a Finding and carries no evidence strength.")
    end

    def readings_in(window)
      readings.select { |reading| window.cover?(reading.at) }
    end

    private

    def readings_relation
      window_observations.where(semantic_key: semantic_key)
    end

    def window_observations
      for_tenant(Observation.all)
        .where(subject_id: subject.id)
        .where(observed_at: baseline.from...selection.to)
        .where(quality_state: "observed")
    end

    # Same organization, same semantic key, same window — and deliberately not
    # filtered to the Case's program, because domain membership lives on the
    # Case rather than on the Observation and inferring it here would put a
    # disease-shaped assumption in platform core.
    def cohort_relation
      for_tenant(Observation.all)
        .where(semantic_key: semantic_key)
        .where(observed_at: baseline.from...selection.to)
        .where(quality_state: "observed")
    end

    def cohort_rows
      @cohort_rows ||= cohort_relation.pluck(:observed_at, :value_numeric)
    end

    def cohort_values
      @cohort_values ||= cohort_rows.filter_map { |_, value| value&.to_f }
    end

    def coverage_for(window)
      covered = readings_in(window).map { |reading| reading.at.to_date }.uniq.size
      total = window.days
      "#{covered}/#{total}"
    end

    def events_in(window)
      for_tenant(Observation.all)
        .where(subject_id: subject.id, semantic_key: semantic_key, quality_state: "observed")
        .where(observed_at: window.from...window.to)
        .distinct.count(:observation_group_id)
    end

    def recording_method_profile
      build_profile(:recording_method, "Recording method", :measurement,
                    "How the reading was taken. A change here can look exactly like a change in the subject (STAT-003).") do |reading|
        reading.recording_method.presence || "unrecorded"
      end
    end

    def quality_state_profile
      build_profile(:quality_state, "Quality state", :measurement,
                    "The missingness taxonomy, never a boolean (STAT-010).") do |reading|
        reading.quality_state
      end
    end

    def source_profile
      by_source = for_tenant(Observation.all)
        .where(subject_id: subject.id, semantic_key: semantic_key, quality_state: "observed")
        .where(observed_at: baseline.from...selection.to)
        .joins(:source)
        .pluck(Arel.sql("sources.key"), :observed_at)

      counts = Hash.new { |hash, key| hash[key] = { baseline: 0, selection: 0 } }
      by_source.each do |key, observed_at|
        bucket = selection.cover?(observed_at) ? :selection : :baseline
        counts[key][bucket] += 1
      end

      rows_from(counts, :source, "Source", :measurement,
                "Which system the reading arrived from. A source change above 30% caps biological evidence at WEAK (STAT-008).")
    end

    def build_profile(key, label, kind, note)
      counts = Hash.new { |hash, bucket| hash[bucket] = { baseline: 0, selection: 0 } }

      readings.each do |reading|
        bucket = selection.cover?(reading.at) ? :selection : :baseline
        counts[yield(reading)][bucket] += 1
      end

      rows_from(counts, key, label, kind, note)
    end

    def rows_from(counts, key, label, kind, note)
      return nil if counts.empty?

      baseline_total = counts.values.sum { |c| c[:baseline] }
      selection_total = counts.values.sum { |c| c[:selection] }
      return nil if baseline_total.zero? && selection_total.zero?

      rows = counts.sort_by { |value, c| [ -(c[:baseline] + c[:selection]), value.to_s ] }.map do |value, c|
        ProfileRow.new(
          label: value.to_s.tr("_", " "),
          baseline_count: c[:baseline], selection_count: c[:selection],
          baseline_share: share(c[:baseline], baseline_total),
          selection_share: share(c[:selection], selection_total)
        )
      end

      Profile.new(key: key, label: label, kind: kind, note: note, rows: rows,
                  baseline_total: baseline_total, selection_total: selection_total,
                  unit_label: "readings")
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
