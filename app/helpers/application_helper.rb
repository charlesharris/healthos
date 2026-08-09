# frozen_string_literal: true

module ApplicationHelper
  # Two letters for the avatar in the top bar. Derived from the email local
  # part because that is the only identifier a User is guaranteed to have —
  # there is no name field, and inventing one from the address would be worse
  # than initials.
  def user_initials(user)
    local = user&.email_address.to_s.split("@").first.to_s
    parts = local.split(/[._\-+]/).reject(&:blank?)

    if parts.length >= 2
      "#{parts[0][0]}#{parts[1][0]}".upcase
    else
      local[0, 2].to_s.upcase.presence || "??"
    end
  end

  # A rail entry that knows whether it is the current surface. `match` is a
  # path prefix rather than an exact comparison so that a Case detail page
  # keeps the Queue entry lit.
  def rail_item(label, path, match: path, count: nil)
    active = request.path.start_with?(match)

    link_to path, class: class_names("rail-item", "is-active" => active),
                  aria: { current: active ? "page" : nil } do
      safe_join([ tag.span(label), (tag.span(count, class: "count") if count) ].compact)
    end
  end

  # Absolute timestamp in the title, compact form in the text. Provider tools
  # get read across shifts and time zones; "2h" is what you scan, the exact
  # instant is what you quote in a note.
  def timestamp(time, format: :long)
    return tag.span(class: "nodata") if time.blank?

    tag.time(l(time.in_time_zone, format: format), datetime: time.iso8601, title: time.utc.iso8601)
  end
end
