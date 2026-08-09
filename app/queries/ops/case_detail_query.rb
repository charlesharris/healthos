# frozen_string_literal: true

module Ops
  # One Case, for Quick Review (HO §88) and for the action controllers.
  #
  # A Tenanted::Query rather than a bare `find` in the controller (INV-31,
  # HO §12). The tenant predicate is in the WHERE clause, so a Case id from
  # another organization does not resolve at all — ApplicationController turns
  # the resulting RecordNotFound into a 404, which also refuses to confirm
  # that the id exists somewhere else (HO §123).
  class CaseDetailQuery < Tenanted::Query
    def initialize(organization:, id:, membership: nil)
      super(organization: organization, membership: membership)
      @id = id
    end

    def resolve
      @case_record ||= for_tenant(Cases::CaseRecord.all)
        .includes(:subject, :owner, :team)
        .find_by!(id: @id)
    end

    # "Why is this here?" (HO §88). The attachments in the order they were
    # made, with the Signal and the persisted correlation explanation (§158),
    # so the answer is the actual evidence rather than a restatement of the
    # Case title.
    def signal_attachments
      resolve.case_signals.includes(:signal).order(:attached_at)
    end

    def trigger_attachments
      signal_attachments.select { |attachment| attachment.relationship == "trigger" }
    end

    def other_attachments
      signal_attachments.reject { |attachment| attachment.relationship == "trigger" }
    end

    def timeline = timeline_query.resolve

    # Surfaced so the view can say the reading cap was hit. A history that
    # stops silently reads as "this is everything that happened".
    def timeline_truncated? = timeline_query.truncated?

    # The windows the picture is drawn over.
    #
    # Taken from the trigger Signal rather than chosen here, so the chart shows
    # the window the monitor actually looked at. A chart drawn over a window of
    # the UI's own invention would illustrate a claim nobody made — and would
    # quietly disagree with the numbers in the Signal beside it.
    # `selection` is the operator's dragged region, or nil for the Signal's
    # own window. Either way the RANGE stays what the monitor looked at, so
    # dragging changes what is selected rather than what is on screen and two
    # selections over the same Case stay comparable.
    def telemetry_profile(semantic_key: nil, selection: nil, filters: {}, baseline_mode: nil)
      bounds = signal_bounds
      return nil if bounds.nil?

      range = TelemetryProfileQuery::Window.new(from: bounds[:range_from], to: bounds[:to])

      TelemetryProfileQuery.new(
        organization: organization, membership: membership,
        subject: resolve.subject, range: range,
        selection: selection&.clamp_to(range) || bounds[:selection],
        semantic_key: semantic_key, preferred_keys: domain_pack_key_order,
        filters: filters, baseline_mode: baseline_mode
      )
    end

    private

    def timeline_query
      @timeline_query ||= Cases::TimelineQuery.new(
        organization: organization, membership: membership, case_record: resolve
      )
    end

    # Which measure to plot first, asked of the domain pack rather than
    # decided here — platform core contains no disease-specific assumption
    # (INV-35), so it reads the pack's declared order instead of naming a key.
    # A Case whose type has no context definition simply gets no preference.
    def domain_pack_key_order
      Array(Analysis::ContextDefinition.find(resolve.case_type).parameters[:biological_keys])
    rescue ArgumentError, NameError
      []
    end

    def signal_bounds
      signal = trigger_attachments.first&.signal

      selection_from, selection_to =
        if signal
          [ signal.window_started_at, signal.window_ended_at || signal.detected_at ]
        else
          # No trigger Signal: fall back to the week before detection, which is
          # what the Case is at least nominally about.
          [ resolve.detected_at - 7.days, resolve.detected_at ]
        end
      return nil if selection_from.nil? || selection_to.nil?

      baseline_days = signal&.attributes_json&.dig("baseline_window_days").presence ||
                      TelemetryProfileQuery::DEFAULT_BASELINE_DAYS

      {
        range_from: selection_from - baseline_days.to_i.days,
        to: selection_to,
        selection: TelemetryProfileQuery::Selection.new(
          from: selection_from, to: selection_to, origin: :signal
        )
      }
    end
  end
end
