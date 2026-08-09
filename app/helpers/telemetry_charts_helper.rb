# frozen_string_literal: true

# Geometry for the Quick Review distribution chart.
#
# Kept out of the template because the arithmetic is the part worth reading
# twice, and because "where does this value sit on the y axis" is the sort of
# thing that should be testable without rendering ERB.
#
# The chart has two layers and they answer different questions, which is why
# they are drawn differently rather than in two shades of the same thing:
#
#   density  — the whole program's readings on these axes. This is the layer
#              that can carry a heatmap, because 47 subjects measuring daily
#              actually fills one. It is CONTEXT, not the evidence for the
#              Case: the monitor that raised the Case looked at one subject.
#
#   subject  — this subject's own readings, drawn as discrete marks. Twenty-one
#              readings cannot fill a heatmap; binning them into cells of
#              exactly 1 would be a scatter plot wearing a heatmap's clothes,
#              and would imply a density that is not in the data.
module TelemetryChartsHelper
  VIEW_W = 800
  VIEW_H = 264
  PAD = { left: 46, right: 10, top: 10, bottom: 40 }.freeze
  DENSITY_STEPS = 5

  Geometry = Struct.new(
    :view_box, :plot_left, :plot_top, :plot_width, :plot_height,
    :cell_width, :band_height, :days, :bands, :band_size,
    :value_min, :value_max, keyword_init: true
  ) do
    def x_for_day(index) = plot_left + (index * cell_width)
    def day_center(index) = x_for_day(index) + (cell_width / 2.0)

    def y_for_band(index) = plot_top + plot_height - ((index + 1) * band_height)

    # Exact position within the band, so a reading of 148 does not render at
    # the same height as one of 141.
    def y_for_value(value)
      span = (value_max - value_min).to_f
      return plot_top + plot_height if span.zero?

      plot_top + plot_height - (((value - value_min) / span) * plot_height)
    end

    def plot_bottom = plot_top + plot_height
    def plot_right = plot_left + plot_width
  end

  def telemetry_geometry(profile)
    days = profile.days.length
    bands = profile.value_bands.length
    plot_width = VIEW_W - PAD[:left] - PAD[:right]
    plot_height = VIEW_H - PAD[:top] - PAD[:bottom]

    Geometry.new(
      view_box: "0 0 #{VIEW_W} #{VIEW_H}",
      plot_left: PAD[:left], plot_top: PAD[:top],
      plot_width: plot_width, plot_height: plot_height,
      cell_width: days.zero? ? 0 : plot_width / days.to_f,
      band_height: bands.zero? ? 0 : plot_height / bands.to_f,
      days: days, bands: bands, band_size: profile.band_size,
      value_min: profile.value_bands.first.to_f,
      value_max: (profile.value_bands.last.to_f + profile.band_size)
    )
  end

  # Count → ramp step, with the edges computed once and published to the
  # legend, because a colour scale whose thresholds are secret is decoration.
  #
  # Five classes, not more: past roughly seven, adjacent classes blur and the
  # reader is doing colour arithmetic instead of reading a chart.
  def density_scale(max_count)
    return [] if max_count.to_i < 1

    width = [ (max_count / DENSITY_STEPS.to_f).ceil, 1 ].max
    (0...DENSITY_STEPS).map do |index|
      low = (index * width) + 1
      high = [ (index + 1) * width, max_count ].min
      next if low > max_count

      { step: index + 1, low: low, high: high }
    end.compact
  end

  def density_step_for(count, max_count)
    scale = density_scale(max_count)
    match = scale.find { |band| count >= band[:low] && count <= band[:high] }
    (match || scale.last)&.fetch(:step) || 1
  end

  # Weekly ticks, plus the first and last day. Denser than that and the labels
  # collide at this width; sparser and the window brackets have nothing to sit
  # against.
  def telemetry_day_ticks(profile)
    total = profile.days.length
    return [] if total.zero?

    indexes = (0...total).step(7).to_a
    indexes << total - 1 unless indexes.include?(total - 1)
    indexes.map { |index| [ index, profile.days[index] ] }
  end

  def telemetry_window_span(profile, window, geometry)
    first = profile.days.index(window.from.to_date)
    last = profile.days.rindex { |day| day < window.to.to_date }
    return nil if first.nil? || last.nil? || last < first

    { x: geometry.x_for_day(first),
      width: geometry.x_for_day(last + 1) - geometry.x_for_day(first) }
  end

  def format_share(share)
    return "—" if share.nil?

    "#{(share * 100).round}%"
  end
end
