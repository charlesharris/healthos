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

    def timeline
      Cases::TimelineQuery.new(
        organization: organization, membership: membership, case_record: resolve
      ).resolve
    end

    # The windows the picture is drawn over.
    #
    # Taken from the trigger Signal rather than chosen here, so the chart shows
    # the window the monitor actually looked at. A chart drawn over a window of
    # the UI's own invention would illustrate a claim nobody made — and would
    # quietly disagree with the numbers in the Signal beside it.
    def telemetry_profile(semantic_key: nil)
      selection, baseline = windows
      return nil if selection.nil?

      TelemetryProfileQuery.new(
        organization: organization, membership: membership,
        subject: resolve.subject, selection: selection, baseline: baseline,
        semantic_key: semantic_key, preferred_keys: domain_pack_key_order
      )
    end

    private

    # Which measure to plot first, asked of the domain pack rather than
    # decided here — platform core contains no disease-specific assumption
    # (INV-35), so it reads the pack's declared order instead of naming a key.
    # A Case whose type has no context definition simply gets no preference.
    def domain_pack_key_order
      Array(Analysis::ContextDefinition.find(resolve.case_type).parameters[:biological_keys])
    rescue ArgumentError, NameError
      []
    end

    def windows
      signal = trigger_attachments.first&.signal

      selection_from, selection_to =
        if signal
          [ signal.window_started_at, signal.window_ended_at || signal.detected_at ]
        else
          # No trigger Signal: fall back to the week before detection, which is
          # what the Case is at least nominally about. Labelled "recent" rather
          # than borrowing a monitor's vocabulary for a window no monitor chose.
          [ resolve.detected_at - 7.days, resolve.detected_at ]
        end
      return [ nil, nil ] if selection_from.nil? || selection_to.nil?

      baseline_days = signal&.attributes_json&.dig("baseline_window_days").presence ||
                      TelemetryProfileQuery::DEFAULT_BASELINE_DAYS

      [
        TelemetryProfileQuery::Window.new(from: selection_from, to: selection_to, label: "selection"),
        TelemetryProfileQuery::Window.new(from: selection_from - baseline_days.to_i.days,
                                          to: selection_from, label: "baseline")
      ]
    end
  end
end
