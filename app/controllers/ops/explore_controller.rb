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

    # Resolved through the tenant scope, never by bare find: a handle from
    # another organization must not resolve at all (INV-31). Absent rather
    # than 404 for an unknown handle — a stale drill-down link should show the
    # cohort, not an error page.
    def focused_subject
      handle = @filters["subject"]
      return nil if handle.blank?

      Subject.find_by(organization_id: Current.organization.id, public_id: handle)
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
