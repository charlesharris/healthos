# frozen_string_literal: true

# A recording device (HO §20). Transitions must be queryable: STAT-007
# evaluates instrumentation before biology, and STAT-008/009 cap or suppress
# biological evidence when the recording source changed mid-window.
class Device < ApplicationRecord
  belongs_to :organization
  belongs_to :source
  belongs_to :subject, optional: true
  has_many :observations, dependent: :nullify

  validates :external_id, :active_from, presence: true

  scope :active_at, lambda { |time|
    where(active_from: ..time).where("active_to IS NULL OR active_to >= ?", time)
  }

  # The query STAT-008/009 depend on: which devices recorded for this subject
  # across a window. More than one means the source mix changed.
  scope :active_during, lambda { |from, to|
    where(active_from: ..to).where("active_to IS NULL OR active_to >= ?", from)
  }

  def active? = active_to.nil?
end
