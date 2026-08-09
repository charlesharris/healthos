# frozen_string_literal: true

# A record that a monitor ran (HO §32).
#
# Exists to answer "why did a Signal exist — or not exist?" A monitor that
# declines to fire is as interesting as one that fires, and without this the
# negative case leaves no trace. Append-only: it is a record of something that
# happened.
class MonitorEvaluation < ApplicationRecord
  RESULTS = %w[triggered not_triggered insufficient_data skipped error].freeze

  belongs_to :organization
  belongs_to :subject
  belongs_to :signal, optional: true, class_name: "Monitoring::Signal"

  validates :monitor_key, :monitor_version, :evaluated_at,
    :window_started_at, :window_ended_at, presence: true
  validates :result, inclusion: { in: RESULTS }

  scope :recent, -> { order(evaluated_at: :desc) }

  def readonly? = persisted?
end
