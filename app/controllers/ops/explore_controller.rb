# frozen_string_literal: true

module Ops
  # Cohort-wide exploration: the whole organization's readings on one pair of
  # axes, with a draggable region and a descriptive breakdown of what is in it.
  #
  # This is where a heatmap earns its keep. One subject measuring daily gives
  # ~21 readings over three weeks, which cannot fill a heatmap; the cohort
  # gives thousands, and "which subjects, which devices, which sources are in
  # this region" is a question only the cohort can answer.
  #
  # Read-only by construction. There is no action here that writes anything
  # except the access audit, and there is no state to write to — the surface
  # produces no artifacts. Whatever an operator notices here becomes a Case
  # through a Monitor, or it becomes nothing (S2C-003: Monitors create Signals,
  # and nothing else creates Cases).
  #
  # NOT the Investigation Workbench. That is Epic 004 and needs the
  # Comparison/Difference artifacts from Epic 003 to rank anything; this
  # surface deliberately ranks nothing and saves nothing, so it cannot quietly
  # become a findings tool without someone noticing.
  class ExploreController < ApplicationController
    DEFAULT_DAYS = 28
    MAX_DAYS = 180

    # How the view is split into panels.
    #
    # Honeycomb puts every event on one heatmap because everything it plots is
    # `duration_ms`. Health telemetry cannot do that: mmHg and bpm on one axis
    # is the dual-axis chart, which invents a correlation out of an arbitrary
    # alignment of two scales. The honest equivalent is small multiples — one
    # panel per measure, or one per value of a dimension.
    #
    # Splitting by a dimension is also the cohort comparison an operator
    # actually wants: device-measured beside manually-entered, on the same
    # axes, over the same days.
    SPLITS = {
      "none" => "Everything together",
      "measure" => "By measure",
      "recording_method" => "By recording method",
      "source" => "By source"
    }.freeze

    # More than this and each panel is too small to read a distribution in.
    MAX_PANELS = 6

    Panel = Struct.new(:label, :sublabel, :profile, :panel_filters, keyword_init: true)

    def show
      authorize_queue!

      @range = resolve_range
      @filters = scope_filters
      @telemetry = TelemetryProfileQuery.new(
        organization: Current.organization, membership: Current.membership,
        range: @range,
        # Drilling all the way down to one subject turns the cohort view into
        # that subject's view: their readings appear as marks over the program
        # density they came from, which is the whole point of having drilled.
        subject: focused_subject,
        selection: TelemetryProfileQuery::Selection.from_params(params)&.clamp_to(@range) ||
                   default_selection,
        semantic_key: params[:key].presence,
        preferred_keys: Analysis::ContextDefinition.declared_key_order,
        filters: @filters,
        baseline_mode: params[:baseline]
      )

      # Drilled all the way to one subject: show the work that already exists
      # for them. Explore notices things; only a Monitor opens a Case
      # (S2C-003), so the way out of here is into work, never into creating it.
      @subject_cases = cases_for_focused_subject

      @cohort_baselines =
        if @telemetry.cohort_baseline? && @telemetry.semantic_key
          CohortBaselineQuery.new(
            organization: Current.organization, membership: Current.membership,
            semantic_key: @telemetry.semantic_key, exclude_subject: focused_subject
          )
        end

      @split = SPLITS.key?(params[:split].to_s) ? params[:split].to_s : "none"
      @panels = build_panels
      # One colour scale across every panel. Scaling each to its own maximum
      # would make a facet holding three readings look exactly as dense as one
      # holding thirty, which is the whole thing small multiples exist to let
      # you see.
      @density_max = @panels.map { |panel| panel.profile.max_cell_count }.max.to_i

      # HO §92: reading cohort telemetry is provider access to health data,
      # however it is aggregated. One event for the query rather than one per
      # subject — the filter set is what identifies the read, and a row per
      # subject would make the audit unreadable at exactly the moment somebody
      # needed to read it.
      AuditEvent.record!(
        event_type: "telemetry.explored", actor: Current.user,
        organization: Current.organization,
        metadata: {
          "semantic_key" => @telemetry.semantic_key,
          "from" => @range.from.iso8601, "to" => @range.to.iso8601,
          "selection" => @telemetry.selection.to_params.transform_keys(&:to_s)
        }
      )
    end

    private

    # Through CaseQuery so the tenant predicate is in the WHERE clause like
    # every other read of Case data (INV-31), and so these rows render with
    # the same partial — and therefore the same assign/triage affordances —
    # as the queue itself.
    def cases_for_focused_subject
      return nil if focused_subject.nil?

      CaseQuery.new(
        organization: Current.organization, membership: Current.membership,
        subject: focused_subject, status: nil, sort: "detected_at", per_page: 10
      ).resolve
    end

    def build_panels
      case @split
      when "measure" then measure_panels
      when "none" then [ Panel.new(profile: @telemetry, panel_filters: {}) ]
      else dimension_panels(@split)
      end
    end

    # One panel per measure the organization actually records. Axes are NOT
    # shared here — mmHg and bpm are different quantities, and forcing them
    # onto one scale would be the dual-axis mistake wearing a different hat.
    def measure_panels
      @telemetry.available_keys.first(MAX_PANELS).map do |key|
        Panel.new(label: short_key(key), profile: profile_for(semantic_key: key), panel_filters: {})
      end
    end

    # One panel per value of a dimension, on SHARED axes — same measure, same
    # days, same bands — because the panels only mean anything set beside each
    # other. The bands come from the unsplit view so no panel can scale itself.
    def dimension_panels(dimension)
      values = distinct_values(dimension).first(MAX_PANELS)
      return [ Panel.new(profile: @telemetry, panel_filters: {}) ] if values.length < 2

      bands = @telemetry.value_bands

      values.map do |value|
        Panel.new(
          label: Ops::TelemetryProfileQuery.filter_value_label(dimension, value),
          sublabel: Ops::TelemetryProfileQuery.filter_label(dimension),
          panel_filters: { dimension => value },
          profile: profile_for(filters: @filters.merge(dimension => value), value_bands: bands)
        )
      end
    end

    def profile_for(semantic_key: @telemetry.semantic_key, filters: @filters, value_bands: nil)
      TelemetryProfileQuery.new(
        organization: Current.organization, membership: Current.membership,
        range: @range, subject: focused_subject,
        selection: @telemetry.selection, semantic_key: semantic_key,
        preferred_keys: Analysis::ContextDefinition.declared_key_order,
        filters: filters, baseline_mode: params[:baseline], value_bands: value_bands
      )
    end

    # Ordered by how much data each value carries, so the busiest facets are
    # the ones that survive MAX_PANELS. The query owns the lookup — it owns
    # the whitelist those dimensions come from.
    def distinct_values(dimension) = @telemetry.distinct_values_for(dimension)

    def short_key(key) = key.split(".").last.tr("_", " ")

    # Resolved through the tenant scope, never by bare find: a handle from
    # another organization must not resolve at all (INV-31). Absent rather
    # than 404 for an unknown handle — a stale drill-down link should show the
    # cohort, not an error page.
    def focused_subject
      return @focused_subject if defined?(@focused_subject)

      handle = @filters["subject"]
      @focused_subject =
        handle.blank? ? nil : Subject.find_by(organization_id: Current.organization.id, public_id: handle)
    end

    def resolve_range
      to = parse_date(params[:range_to]) || Date.current + 1
      from = parse_date(params[:range_from]) || to - DEFAULT_DAYS

      # Clamped rather than refused: an operator who types a year into a date
      # field has made a typo, and a 500 teaches them nothing.
      from = to - MAX_DAYS if (to - from).to_i > MAX_DAYS
      from = to - 1 if from >= to

      TelemetryProfileQuery::Window.new(from: from.beginning_of_day, to: to.beginning_of_day)
    end

    # Nothing selected by default. The operator has not asked a question yet,
    # and pre-selecting a region would answer one they did not ask.
    def default_selection
      TelemetryProfileQuery::Selection.new(
        from: @range.to, to: @range.to + 1.second, origin: :none
      )
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
