# frozen_string_literal: true

# Organization-specific monitor configuration (HO §31).
#
# Separate from the monitor definition so customer policy can set thresholds
# without changing code identity — and so platform core ships no clinical
# defaults of its own. Defaults live in the domain pack; this overrides them.
class MonitorConfiguration < ApplicationRecord
  belongs_to :organization

  validates :domain_key, :monitor_key, :monitor_version, presence: true
  validates :monitor_key, uniqueness: { scope: %i[organization_id monitor_version] }

  scope :enabled, -> { where(enabled: true) }

  def monitor_class = Monitoring::Monitor.find(monitor_key)

  # Domain-pack defaults, overridden by whatever this organization set.
  def effective_parameters
    monitor_class.default_parameters.merge(parameters.symbolize_keys)
  end
end
