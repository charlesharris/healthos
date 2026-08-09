# frozen_string_literal: true

require "rails_helper"

# The Quick Review distribution chart and its "what was different?" strip.
#
# HO §84 ("show me what was different, then show me the evidence"), STAT-002,
# STAT-003, STAT-004/005/021, STAT-019/024, STAT-035.
#
# These are contract specs, not rendering specs. What they hold down is that
# the picture cannot say something the contract forbids: that absence is not
# zero, that the denominators travel with the shares, that measurement
# dimensions come before biological ones, and that nothing here claims
# evidence strength.
RSpec.describe "Quick Review telemetry profile", type: :model do
  include TelemetryChartsHelper

  let!(:organization) { create_organization(name: "Northside", slug: "northside") }
  let!(:other_organization) { create_organization(name: "Southside", slug: "southside") }
  let!(:subject_record) { Subject.create!(organization: organization, timezone: "UTC") }

  let!(:cuff) do
    Source.create!(organization: organization, key: "cuff", source_type: "device_cloud",
                   display_name: "BP cuff")
  end
  let!(:manual) do
    Source.create!(organization: organization, key: "manual", source_type: "manual",
                   display_name: "Manual entry")
  end
  let!(:envelope) do
    RawEnvelope.create!(
      organization: organization, source: cuff, source_record_id: "r1",
      content_type: "application/json", object_key: "k", content_hash: "h",
      received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
    )
  end

  let(:key) { "health.vital.blood_pressure.systolic" }
  let(:anchor) { Time.utc(2026, 3, 22, 0, 0) }

  # The RANGE is what the chart draws; the SELECTION is the region inside it
  # being asked about. Baseline is the complement — everything in range that
  # the selection does not cover — so dragging changes what is compared
  # without changing what is on screen.
  let(:range) do
    Ops::TelemetryProfileQuery::Window.new(from: anchor - 28.days, to: anchor)
  end
  let(:selection) do
    Ops::TelemetryProfileQuery::Selection.new(from: anchor - 7.days, to: anchor, origin: :signal)
  end

  # `minute` exists because observations carry a unique normalization identity
  # on (envelope, key, version, observed_at) — two readings at the same instant
  # from one envelope is a duplicate, not a second measurement.
  def observe(days_ago:, value: 120, source: cuff, method: "device_automatic",
              subject: subject_record, org: organization, group: nil, minute: 0)
    Observation.create!(
      organization: org, subject: subject, source: source, raw_envelope: envelope,
      source_record_id: "r-#{subject.id}-#{days_ago}-#{method}-#{value}",
      semantic_key: key, semantic_version: 1, value_numeric: value, unit: "mmHg",
      observation_group: group,
      observed_at: anchor - days_ago.days + 12.hours + minute.minutes, normalized_at: Time.current,
      quality_state: "observed", recording_method: method,
      normalizer_key: "synthetic_bp_json", normalizer_version: 1
    )
  end

  def profile(semantic_key: nil, preferred_keys: [], subject: subject_record, selected: selection)
    Ops::TelemetryProfileQuery.new(
      organization: organization, subject: subject, range: range, selection: selected,
      semantic_key: semantic_key, preferred_keys: preferred_keys
    )
  end

  describe "STAT-002 absence is never zero" do
    it "names the days with no reading rather than plotting them as a value" do
      observe(days_ago: 20)
      observe(days_ago: 3)

      result = profile

      expect(result.days_without_readings.length).to eq(result.days.length - 2)
      expect(result.days_without_readings).to include(anchor.to_date - 10)
      expect(result.readings.map(&:value)).to all(be_present)
    end

    # The chart draws a hatch for these days. A day with no measurement and a
    # day with a measurement of zero are different facts, and only one of them
    # is possible for blood pressure.
    it "keeps missing days out of the readings entirely" do
      observe(days_ago: 3)

      expect(profile.readings.length).to eq(1)
    end
  end

  describe "STAT-004/005/021 denominators" do
    it "counts measurement events and raw readings separately" do
      group = ObservationGroup.create!(
        organization: organization, subject: subject_record, source: cuff,
        raw_envelope: envelope, semantic_key: "health.vital.blood_pressure",
        semantic_version: 1, observed_at: anchor - 3.days + 12.hours
      )
      observe(days_ago: 3, value: 120, group: group, minute: 0)
      observe(days_ago: 3, value: 122, group: group, minute: 1)

      stats = profile.coverage_stats.index_by(&:label)

      expect(stats["Readings"].selection).to eq(2)
      expect(stats["Measurement events"].selection).to eq(1)
    end

    it "states coverage as days covered out of days in the window" do
      observe(days_ago: 3)
      observe(days_ago: 4)

      stats = profile.coverage_stats.index_by(&:label)

      expect(stats["Days with a reading"].selection).to eq("2/7")
      expect(stats["Days with a reading"].baseline).to eq("0/21")
    end

    it "carries a denominator on every dimension profile" do
      observe(days_ago: 20)
      observe(days_ago: 3)

      profile.profiles.each do |dimension|
        expect(dimension.baseline_total + dimension.selection_total).to be_positive
      end
    end
  end

  describe "STAT-019/024/035 ordering" do
    # Honeycomb sorts these by how different they are. This cannot: a source
    # change that moves 14 readings outranks a 40 mmHg shift, and sorting by
    # effect size would put them the other way round.
    it "puts every measurement dimension before the biological summary" do
      observe(days_ago: 20, value: 118)
      observe(days_ago: 3, value: 160, source: manual, method: "manual_entry")

      result = profile

      expect(result.profiles.map(&:kind).uniq).to eq([ :measurement ])
      expect(result.value_summary).to be_present
    end

    it "exposes no evidence strength, score or rank of any kind" do
      observe(days_ago: 20)
      observe(days_ago: 3)

      result = profile

      expect(result).not_to respond_to(:evidence_level)
      expect(result).not_to respond_to(:score)
      expect(result).not_to respond_to(:rank)

      # The rows carry counts and shares and nothing else. (The notes DO name
      # WEAK — quoting STAT-008's rule about what a source change caps
      # evidence at — which is a citation of the contract, not a claim about
      # this comparison. The distinction is the point: this object reports
      # what is in the database and defers judgement to an artifact.)
      # Counts, shares, and the identifiers needed to label and drill into a
      # row. Nothing that grades it.
      row = result.profiles.first.rows.first
      expect(row.members).to contain_exactly(
        :label, :value, :handle, :baseline_count, :selection_count, :baseline_share, :selection_share
      )
    end

    # A Difference is descriptive, never causal — in code and in UI copy.
    it "describes the biological summary without claiming it is a finding" do
      observe(days_ago: 20, value: 118)
      observe(days_ago: 3, value: 160)

      expect(profile.value_summary.note).to match(/not a Finding/i)
    end
  end

  describe "STAT-003 measurement behaviour is first-class" do
    it "reports a recording-method change as its own dimension with shares" do
      2.times { |i| observe(days_ago: 20 + i, method: "device_automatic") }
      observe(days_ago: 3, method: "manual_entry", source: manual)

      method_profile = profile.profiles.find { |d| d.key == :recording_method }
      manual_row = method_profile.rows.find { |row| row.label == "manual entry" }

      expect(manual_row.baseline_share).to eq(0.0)
      expect(manual_row.selection_share).to eq(1.0)
      expect(method_profile).not_to be_unchanged
    end

    it "still reports a dimension that did not move, rather than dropping it" do
      observe(days_ago: 20)
      observe(days_ago: 3)

      method_profile = profile.profiles.find { |d| d.key == :recording_method }

      expect(method_profile).to be_unchanged
      expect(method_profile.rows.first.label).to eq("device automatic")
    end
  end

  describe "the density layer" do
    it "counts the whole organization, since one subject cannot fill a heatmap" do
      other = Subject.create!(organization: organization, timezone: "UTC")
      observe(days_ago: 3, value: 120, minute: 0)
      observe(days_ago: 3, value: 122, subject: other, minute: 1)

      result = profile

      expect(result.readings.length).to eq(1)
      expect(result.cohort_cells.sum(&:count)).to eq(2)
      expect(result.cohort_subject_count).to eq(2)
    end

    # INV-31. The density layer reads across subjects, which makes forgetting
    # the tenant predicate here more consequential than anywhere else on this
    # screen.
    it "never counts another organization's readings" do
      foreign_subject = Subject.create!(organization: other_organization, timezone: "UTC")
      foreign_source = Source.create!(organization: other_organization, key: "cuff",
                                      source_type: "device_cloud", display_name: "BP cuff")
      foreign_envelope = RawEnvelope.create!(
        organization: other_organization, source: foreign_source, source_record_id: "r9",
        content_type: "application/json", object_key: "k9", content_hash: "h9",
        received_at: Time.current, adapter_key: "synthetic_bp_json", adapter_version: "1"
      )
      Observation.create!(
        organization: other_organization, subject: foreign_subject, source: foreign_source,
        raw_envelope: foreign_envelope, source_record_id: "foreign-1",
        semantic_key: key, semantic_version: 1, value_numeric: 130, unit: "mmHg",
        observed_at: anchor - 3.days, normalized_at: Time.current, quality_state: "observed",
        recording_method: "device_automatic", normalizer_key: "synthetic_bp_json",
        normalizer_version: 1
      )
      observe(days_ago: 3)

      expect(profile.cohort_cells.sum(&:count)).to eq(1)
      expect(profile.cohort_subject_count).to eq(1)
    end
  end

  describe "which measure is plotted" do
    it "follows the domain pack's declared order rather than an alphabetical tie" do
      observe(days_ago: 3, value: 120)
      Observation.create!(
        organization: organization, subject: subject_record, source: cuff,
        raw_envelope: envelope, source_record_id: "dia-1",
        semantic_key: "health.vital.blood_pressure.diastolic", semantic_version: 1,
        value_numeric: 80, unit: "mmHg", observed_at: anchor - 3.days + 12.hours,
        normalized_at: Time.current, quality_state: "observed",
        recording_method: "device_automatic", normalizer_key: "synthetic_bp_json",
        normalizer_version: 1
      )

      preferred = %w[health.vital.blood_pressure.systolic health.vital.blood_pressure.diastolic]

      expect(profile(preferred_keys: preferred).semantic_key).to eq(key)
      expect(profile(preferred_keys: preferred.reverse).semantic_key)
        .to eq("health.vital.blood_pressure.diastolic")
    end

    it "ignores a requested key the subject has no data for" do
      observe(days_ago: 3)

      expect(profile(semantic_key: "health.vital.nonsense").semantic_key).to eq(key)
    end
  end

  describe "the dragged selection" do
    let(:custom) do
      Ops::TelemetryProfileQuery::Selection.new(
        from: anchor - 5.days, to: anchor - 2.days, origin: :custom
      )
    end

    # Baseline is the complement, so a region in the MIDDLE of the range still
    # has a baseline on both sides of it. A contiguous baseline window could
    # not express that.
    it "compares the selection against everything outside it, not against a window before it" do
      observe(days_ago: 20)
      observe(days_ago: 4)
      observe(days_ago: 1)

      stats = profile(selected: custom).coverage_stats.index_by(&:label)

      expect(stats["Readings"].selection).to eq(1)
      expect(stats["Readings"].baseline).to eq(2)
    end

    it "restricts the selection to a value box when one is dragged" do
      observe(days_ago: 4, value: 118)
      observe(days_ago: 3, value: 165)

      boxed = Ops::TelemetryProfileQuery::Selection.new(
        from: anchor - 6.days, to: anchor, value_min: 150, value_max: 170, origin: :custom
      )
      stats = profile(selected: boxed).coverage_stats.index_by(&:label)

      expect(stats["Readings"].selection).to eq(1)
      expect(stats["Readings"].baseline).to eq(1)
      expect(profile(selected: boxed)).to be_conditioned_on_value
    end

    # Selecting on the outcome and then reporting which dimensions differ is a
    # hypothesis generator; the differences may exist BECAUSE of the selection.
    # The flag is what the view hangs its warning on.
    it "flags a value-bounded selection and does not flag a time-only one" do
      expect(profile(selected: custom)).not_to be_conditioned_on_value
    end

    # A time-only selection owns its days outright. A value-bounded one does
    # not: a day inside its time range still contributes baseline readings for
    # values outside the box, so both sides see that day. Subtracting anyway
    # printed "21/20" — a numerator above its own denominator.
    describe "the coverage denominator" do
      before do
        observe(days_ago: 20, value: 118)
        observe(days_ago: 3, value: 165)
      end

      # The day-20 reading is outside the selection, the day-3 reading is
      # inside it, and the denominator is the 25 days the selection leaves.
      it "gives the baseline the days the selection does not take" do
        stats = profile(selected: custom).coverage_stats.index_by(&:label)

        expect(stats["Days with a reading"].baseline).to eq("1/25")
        expect(stats["Days with a reading"].selection).to eq("1/3")
      end

      it "gives the baseline the whole range when the selection is a value box" do
        boxed = Ops::TelemetryProfileQuery::Selection.new(
          from: range.from, to: range.to, value_min: 150, value_max: 170, origin: :custom
        )
        stats = profile(selected: boxed).coverage_stats.index_by(&:label)

        covered, total = stats["Days with a reading"].baseline.split("/").map(&:to_i)
        expect(total).to eq(range.days)
        expect(covered).to be <= total
      end
    end

    describe "parsing untrusted parameters" do
      it "reads a well-formed region" do
        parsed = Ops::TelemetryProfileQuery::Selection.from_params(
          from: (anchor - 5.days).iso8601, to: (anchor - 2.days).iso8601, vmin: "150", vmax: "120"
        )

        expect(parsed.from).to eq(anchor - 5.days)
        # Bounds arrive in whichever order the drag produced them.
        expect([ parsed.value_min, parsed.value_max ]).to eq([ 120.0, 150.0 ])
      end

      it "returns nothing for junk rather than raising" do
        expect(Ops::TelemetryProfileQuery::Selection.from_params(from: "nonsense", to: "?")).to be_nil
        expect(Ops::TelemetryProfileQuery::Selection.from_params({})).to be_nil
      end

      it "refuses an inverted or empty region" do
        expect(Ops::TelemetryProfileQuery::Selection.from_params(
          from: anchor.iso8601, to: (anchor - 1.day).iso8601
        )).to be_nil
      end

      # A drag that runs a day past the edge is a fat finger, not an attack.
      it "clamps a region that overruns the chart" do
        overrun = Ops::TelemetryProfileQuery::Selection.new(
          from: anchor - 90.days, to: anchor + 90.days, origin: :custom
        )

        clamped = overrun.clamp_to(range)

        expect(clamped.from).to eq(range.from)
        expect(clamped.to).to eq(range.to)
      end

      it "gives up on a region entirely outside the chart" do
        outside = Ops::TelemetryProfileQuery::Selection.new(
          from: anchor + 10.days, to: anchor + 20.days, origin: :custom
        )

        expect(outside.clamp_to(range)).to be_nil
      end
    end
  end

  # The half of the exploration loop the strip was missing: notice that manual
  # entry is most of a region, scope everything to it, look again.
  describe "drilling into a dimension" do
    before do
      2.times { |i| observe(days_ago: 20 + i, method: "device_automatic") }
      observe(days_ago: 3, method: "manual_entry", source: manual)
    end

    def scoped(filters) = profile(subject: subject_record).then { profile_with(filters) }

    def profile_with(filters)
      Ops::TelemetryProfileQuery.new(
        organization: organization, subject: subject_record, range: range,
        selection: selection, filters: filters
      )
    end

    # The chart and the breakdown must never describe different populations.
    it "narrows the marks, the density and every profile together" do
      scoped = profile_with("recording_method" => "manual_entry")

      expect(scoped.readings.length).to eq(1)
      expect(scoped.cohort_cells.sum(&:count)).to eq(1)
      expect(scoped.coverage_stats.index_by(&:label)["Readings"].selection).to eq(1)
    end

    it "moves the denominators with the scope, which is the point of showing them" do
      unscoped = profile_with({})
      scoped = profile_with("recording_method" => "manual_entry")

      expect(unscoped.coverage_stats.index_by(&:label)["Readings"].baseline).to eq(2)
      expect(scoped.coverage_stats.index_by(&:label)["Readings"].baseline).to eq(0)
    end

    it "filters across an association without raw SQL" do
      scoped = profile_with("source" => "manual")

      expect(scoped.readings.length).to eq(1)
    end

    it "combines filters" do
      expect(profile_with("recording_method" => "manual_entry", "source" => "cuff").readings).to be_empty
      expect(profile_with("recording_method" => "manual_entry", "source" => "manual").readings.length).to eq(1)
    end

    # These keys become column and association names.
    it "ignores a dimension that is not on the whitelist" do
      scoped = profile_with("organization_id" => "whatever", "recording_method" => "manual_entry")

      expect(scoped.filters).to eq("recording_method" => "manual_entry")
      expect(scoped.readings.length).to eq(1)
    end

    it "treats a filter value as a value, never as SQL" do
      scoped = profile_with("recording_method" => "manual_entry'; DROP TABLE observations; --")

      expect(scoped.readings).to be_empty
      expect(Observation.count).to eq(3)
    end

    it "drops a blank filter rather than matching on emptiness" do
      expect(profile_with("recording_method" => "").filters).to be_empty
    end

    # Rows carry the raw value, because the label is prose.
    it "exposes the raw value a row would be filtered by" do
      row = profile_with({}).profiles
        .find { |d| d.key == :recording_method }.rows
        .find { |r| r.label == "manual entry" }

      expect(row.value).to eq("manual_entry")
      expect(row.label).to eq("manual entry")
    end

    it "names the dimensions that can be drilled into" do
      keys = profile_with({}).profiles.filter_map(&:filter_key)

      expect(keys).to include("recording_method", "quality_state", "source")
    end
  end

  describe "cohort mode (Explore)" do
    it "drops the focus subject's marks and profiles the whole organization" do
      other = Subject.create!(organization: organization, timezone: "UTC")
      observe(days_ago: 3, value: 120)
      observe(days_ago: 3, value: 122, subject: other, minute: 1)

      result = profile(subject: nil)

      expect(result).not_to be_focused
      expect(result.readings).to be_empty
      expect(result.days_without_readings).to be_empty
      expect(result.coverage_stats.index_by(&:label)["Readings"].selection).to eq(2)
    end

    # "Which subjects are in this region" is the question a cohort heatmap
    # exists to answer — and the handle stays opaque (HO §92).
    it "adds a subject dimension that never leaves the opaque handle" do
      other = Subject.create!(organization: organization, timezone: "UTC")
      observe(days_ago: 3)
      observe(days_ago: 3, subject: other, minute: 1)

      subject_profile = profile(subject: nil).profiles.find { |d| d.key == :subject }

      expect(subject_profile.kind).to eq(:identity)
      expect(subject_profile.rows.map(&:label))
        .to contain_exactly(subject_record.public_id, other.public_id)
    end

    it "does not add a subject dimension when focused on one subject" do
      observe(days_ago: 3)

      expect(profile.profiles.map(&:key)).not_to include(:subject)
    end

    # No silent caps: a top-N that does not say so reads as "these are all".
    it "folds a long tail into one row and says how many it folded" do
      12.times do |index|
        extra = Subject.create!(organization: organization, timezone: "UTC")
        observe(days_ago: 3, subject: extra, minute: index + 2)
      end

      subject_profile = profile(subject: nil).profiles.find { |d| d.key == :subject }

      expect(subject_profile.rows.length).to eq(Ops::TelemetryProfileQuery::MAX_ROWS + 1)
      expect(subject_profile.rows.last.label).to match(/\Aother \(\d+\)\z/)
      expect(subject_profile.truncated_from).to eq(12)
    end
  end

  # The bug this caught: y_for_band(i) is the TOP of band i, so labelling it
  # with bands[i] put every tick one band low. The chart's own median line then
  # disagreed with the median printed beside it by exactly one band — the data
  # was right and the axis was lying.
  describe "chart geometry" do
    it "maps a band edge to the same y as the band boundary it borders" do
      observe(days_ago: 20, value: 105)
      observe(days_ago: 3, value: 165)

      result = profile
      geometry = telemetry_geometry(result)

      result.value_bands.each_with_index do |band, index|
        expect(geometry.y_for_value(band + result.band_size))
          .to be_within(0.01).of(geometry.y_for_band(index))
      end
    end

    it "puts the lowest band edge on the axis and the highest at the top" do
      observe(days_ago: 3, value: 120)

      result = profile
      geometry = telemetry_geometry(result)

      expect(geometry.y_for_value(geometry.value_min)).to be_within(0.01).of(geometry.plot_bottom)
      expect(geometry.y_for_value(geometry.value_max)).to be_within(0.01).of(geometry.plot_top)
    end

    it "publishes the density scale edges it colours by" do
      expect(density_scale(24).first[:low]).to eq(1)
      expect(density_scale(24).last[:high]).to eq(24)
      expect(density_scale(24).length).to be <= 5
      expect(density_scale(0)).to be_empty
    end
  end
end
