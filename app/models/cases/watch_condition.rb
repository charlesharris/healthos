# frozen_string_literal: true

module Cases
  # An explicit reevaluation condition (HO §45, S2C-014).
  #
  # "Watching means: review occurred, but evidence does not justify closure or
  # immediate action." That is a genuine third answer beside act and close,
  # and it is where STAT-036's "we do not have enough evidence yet" lives
  # operationally — a Case can be honestly parked with a stated condition for
  # coming back, rather than closed to keep the queue tidy.
  class WatchCondition < ApplicationRecord
    CONDITION_TYPES = %w[time_elapsed new_observation_count new_signal threshold_crossed].freeze

    belongs_to :organization
    belongs_to :case_record, class_name: "Cases::CaseRecord", foreign_key: :case_id, inverse_of: :watch_conditions
    belongs_to :created_by, class_name: "User", optional: true

    validates :condition_type, inclusion: { in: CONDITION_TYPES }

    scope :pending, -> { where(satisfied_at: nil) }

    def satisfied? = satisfied_at.present?
    def expired?(at: Time.current) = expires_at.present? && expires_at <= at

    # Whether the condition has been met. Deliberately explicit per type
    # rather than a generic predicate — a watch that silently never fires is
    # worse than no watch at all, because it looks like active monitoring.
    def satisfied_by?(case_record, at: Time.current)
      case condition_type
      when "time_elapsed"
        expires_at.present? && expires_at <= at
      when "new_observation_count"
        observations_since >= parameters.fetch("count", 1).to_i
      when "new_signal"
        case_record.case_signals.where(attached_at: created_at..).count.positive?
      when "threshold_crossed"
        # Evaluated by the monitor that owns the threshold, not here — putting
        # a threshold in a watch condition would duplicate a governed value.
        false
      else
        false
      end
    end

    def observations_since
      Observation
        .where(organization_id: organization_id, subject_id: case_record.subject_id)
        .where(observed_at: created_at..)
        .where(quality_state: "observed")
        .count
    end
  end
end
