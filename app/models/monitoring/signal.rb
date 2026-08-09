# frozen_string_literal: true

module Monitoring
  # Immutable machine evidence (HO §33, S2C-001).
  #
  # A Signal says "something in the data warrants attention." It is not a
  # finding, not a diagnosis, and not a unit of work — Cases are the unit of
  # human work (S2C-004), and many Signals correlate into few Cases (S2C-005).
  #
  # Append-only: if a monitor's logic changes, old Signals are not rewritten.
  # A historical Case may therefore hold Signals from several monitor versions,
  # which HO §9 says "is acceptable and must remain inspectable".
  #
  # Namespaced out of necessity as well as design: `Signal` is a Ruby core
  # module (`Signal.trap`), so a top-level model of that name never takes the
  # constant — references silently resolve to the core module and fail with a
  # confusing NoMethodError. The namespace also matches the
  # app/models/monitoring/ layout CLAUDE.md specifies.
  class Signal < ApplicationRecord
    self.table_name = "signals"

    SEVERITIES = %w[info low moderate high].freeze

    belongs_to :organization
    belongs_to :subject
    has_many :monitor_evaluations, dependent: :nullify,
      class_name: "MonitorEvaluation", inverse_of: :signal

    validates :monitor_key, :monitor_version, :monitor_digest, :signal_type,
      :domain_key, :detected_at, :window_started_at, :deduplication_key, presence: true
    validates :severity, inclusion: { in: SEVERITIES }
    validates :public_id, presence: true, uniqueness: { scope: :organization_id }

    before_validation :assign_public_id, on: :create

    scope :for_domain, ->(domain) { where(domain_key: domain) }
    scope :detected_between, ->(from, to) { where(detected_at: from..to) }

    def readonly? = persisted?

    def monitor = "#{monitor_key}@v#{monitor_version}"

    # HO §34. Derived from organization, subject, monitor key/version,
    # evaluation window, and semantic event identity — hashed so the column
    # stays a fixed width regardless of how long the identity grows.
    def self.deduplication_key_for(organization:, subject:, monitor_key:, monitor_version:,
                                   window:, semantic_identity:)
      Digest::SHA256.hexdigest(
        [
          organization.id, subject.id, monitor_key, monitor_version,
          window.first.utc.iso8601, window.last&.utc&.iso8601, semantic_identity
        ].join(":")
      )
    end

    private

    def assign_public_id
      self.public_id ||= "sig_#{SecureRandom.alphanumeric(20).downcase}"
    end
  end
end
