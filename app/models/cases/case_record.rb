# frozen_string_literal: true

module Cases
  # The stateful unit of human work (HO §36, S2C-004, INV-25).
  #
  # Named CaseRecord because `Case` is too close to Ruby's `case` keyword to
  # be comfortable as a constant, and `Cases::Case` reads poorly. The table is
  # `cases`, which is what the handover and every index reference.
  #
  # Deliberately mutable — this is the one place in the evidence chain where
  # state legitimately changes, because human work has a lifecycle. Its
  # history is preserved separately and immutably in CaseEvent (S2C-010).
  class CaseRecord < ApplicationRecord
    self.table_name = "cases"

    STATUSES = %w[new triaged investigating watching waiting_external resolved dismissed].freeze
    # S2C-018/019: analysis state is independent of operational state. A Case
    # whose analysis failed is still a Case somebody must handle, and `failed`
    # is never conflated with `insufficient_evidence`.
    ANALYSIS_STATUSES = %w[not_started pending current stale failed insufficient_evidence].freeze
    ACTIVE_STATUSES = %w[new triaged investigating watching waiting_external].freeze

    belongs_to :organization
    belongs_to :subject
    belongs_to :owner, class_name: "User", optional: true
    belongs_to :team, optional: true

    has_many :case_signals, dependent: :restrict_with_error, foreign_key: :case_id, inverse_of: :case_record
    has_many :signals, through: :case_signals, source: :signal
    has_many :case_events, -> { order(:occurred_at) }, dependent: :restrict_with_error,
      foreign_key: :case_id, inverse_of: :case_record

    validates :domain_key, :case_type, :started_at, :detected_at, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :analysis_status, inclusion: { in: ANALYSIS_STATUSES }
    validates :public_id, presence: true, uniqueness: { scope: :organization_id }

    before_validation :assign_public_id, on: :create

    scope :active, -> { where(status: ACTIVE_STATUSES) }
    scope :for_domain, ->(domain) { where(domain_key: domain) }

    def active? = ACTIVE_STATUSES.include?(status)
    def resolved? = %w[resolved dismissed].include?(status)

    private

    def assign_public_id
      self.public_id ||= "case_#{SecureRandom.alphanumeric(20).downcase}"
    end
  end
end
