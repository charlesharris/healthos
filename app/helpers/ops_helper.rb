# frozen_string_literal: true

# Presentation for the Ops Queue and Quick Review (HO §84–88).
#
# The rendering rules here are load-bearing, not cosmetic. Two of them exist
# to keep independent axes independent on screen, which is where they are
# most likely to be silently collapsed:
#
#   * Review priority is operational policy and evidence strength is
#     statistical support (S2C-011). Priority gets an emphasis ramp, evidence
#     gets a monochrome meter, and neither borrows the other's vocabulary.
#
#   * `failed` and `insufficient_evidence` are different answers (S2C-019,
#     STAT-036) and are rendered differently, so an honest "no reliable
#     distinguishing pattern" never looks like an incident.
module OpsHelper
  MINUTE = 60
  HOUR = 3600
  DAY = 86_400

  # Compact age for a dense column: "4m", "2h", "3d", "6w".
  #
  # `time_ago_in_words` produced "about 2 hours" and wrapped across five lines
  # in a column sized for one, which is what made the old queue rows 130px
  # tall. The exact instant stays available as the element's title.
  def compact_age(time)
    return tag.span(class: "nodata") if time.blank?

    seconds = [ Time.current - time, 0 ].max

    text =
      case seconds
      when 0...MINUTE      then "now"
      when MINUTE...HOUR   then "#{(seconds / MINUTE).floor}m"
      when HOUR...DAY      then "#{(seconds / HOUR).floor}h"
      when DAY...(DAY * 14) then "#{(seconds / DAY).floor}d"
      else "#{(seconds / (DAY * 7)).floor}w"
      end

    tag.span(text, class: "age tnum", title: time.utc.iso8601)
  end

  # Review priority (S2C-011). Rendered as the word, never a number, and never
  # coloured on a severity ramp — see the .chip-priority-* comment in the
  # stylesheet for why that distinction is a requirement rather than a taste.
  def priority_chip(priority)
    return tag.span(class: "nodata") if priority.blank?

    tag.span(priority, class: "chip chip-priority-#{priority}",
                       title: "Review priority — how soon a human should look. " \
                              "Independent of evidence strength.")
  end

  def status_chip(status)
    return tag.span(class: "nodata") if status.blank?

    tag.span(status.humanize, class: "chip chip-status-#{status}")
  end

  # S2C-019: analysis state is shown and never hides the Case.
  def analysis_chip(status)
    return tag.span(class: "nodata") if status.blank?

    tag.span(status.humanize, class: "chip chip-analysis-#{status}", title: analysis_explanation(status))
  end

  def analysis_explanation(status)
    case status
    when "failed"
      "Analysis did not complete. The Case is unaffected and still needs handling."
    when "insufficient_evidence"
      "Analysis completed and found no reliable distinguishing pattern. That is a result, not a failure."
    when "stale"
      "Late data arrived. New artifacts are being built; this snapshot is superseded."
    when "not_started"
      "No analysis has run for this Case yet."
    end
  end

  EVIDENCE_LEVELS = %w[insufficient weak moderate strong].freeze

  # Evidence strength as a monochrome four-tick meter.
  #
  # Colour is withheld on purpose: evidence strength is support that a
  # dimension differs, NOT severity, causality or importance. A colour ramp
  # would be read as a severity ramp within about a day of shipping.
  def evidence_meter(level)
    return tag.span(class: "nodata") if level.blank?

    filled = EVIDENCE_LEVELS.index(level.to_s)
    return tag.span(level, class: "chip chip-mono") if filled.nil?

    ticks = EVIDENCE_LEVELS.each_index.map do |index|
      tag.span(class: class_names("meter-tick", "is-on" => index <= filled))
    end

    tag.span(class: "meter",
             title: "Evidence strength: support that a dimension differs. " \
                    "Not severity, not importance.") do
      safe_join([ tag.span(safe_join(ticks), class: "meter-ticks"),
                  tag.span(level, class: "meter-label") ])
    end
  end

  # Data quality and baseline maturity are plain labels for now; both become
  # richer in epics 003/004. Rendered rather than hidden when absent, because
  # "nothing has been computed" is information (HO §84).
  def qualitative(value)
    return tag.span(class: "nodata") if value.blank?

    tag.span(value.to_s.humanize, class: "chip")
  end

  # An opaque handle, never a name and never an MRN. Identity is PHI and
  # requires a deliberate, audited read (HO §92).
  def subject_handle(subject, truncate: nil)
    id = subject.public_id
    text = truncate ? id.truncate(truncate, omission: "…") : id

    tag.span(text, class: "handle mono", title: id)
  end

  # Timeline detail, which arrives as a hash on most entries.
  #
  # Dumping it as JSON put `{"quality_state":"observed","unit":"mmHg"}` on
  # every observation row — braces, quotes and colons outnumbering the two
  # facts they carry, repeated down the whole history. Same content, same
  # order, without the punctuation.
  def timeline_detail(detail)
    return if detail.blank?

    unless detail.is_a?(Hash)
      return tag.span(detail, class: "detail")
    end

    pairs = detail.compact.map do |key, value|
      rendered = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value

      safe_join([ tag.span(key.to_s.tr("_", " "), class: "detail-key"), " ", rendered.to_s ])
    end
    return if pairs.empty?

    tag.span(safe_join(pairs, tag.span(" · ", class: "sep")), class: "detail")
  end

  # Priority reasons carry codes like `aged_unreviewed`. The code is the thing
  # an operator learns to recognise, so it is shown verbatim in a code style
  # rather than humanized into prose that reads like a sentence someone wrote.
  def priority_reason_codes(case_record)
    Array(case_record.priority_reasons).filter_map { |reason| reason["code"] }
  end
end
