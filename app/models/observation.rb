# frozen_string_literal: true

# Canonical telemetry (HO §16). Append-only (INV-2): a correction arrives as a
# new observation from a new envelope, never as an edit.
class Observation < ApplicationRecord
  # HO §28 / STAT-010. Ten states, never a boolean.
  QUALITY_STATES = %w[
    observed not_expected expected_but_missing source_unavailable
    device_not_reporting manual_entry_absent invalid_measurement
    excluded_by_rule late_not_yet_arrived unknown
  ].freeze

  # States that represent an absent measurement. STAT-002: absence is never
  # zero, and these rows carry no value at all — the CHECK constraint makes
  # that structural rather than conventional.
  MISSING_STATES = (QUALITY_STATES - %w[observed]).freeze

  # A measurement the protocol expected and did not get. Distinct from
  # not_expected, which is not a gap at all. This is the numerator of the
  # completeness shortfall (SC §14).
  EXPECTED_BUT_ABSENT_STATES = %w[
    expected_but_missing source_unavailable device_not_reporting
    manual_entry_absent late_not_yet_arrived
  ].freeze

  belongs_to :organization
  belongs_to :subject
  belongs_to :source
  belongs_to :raw_envelope
  belongs_to :observation_group, optional: true
  belongs_to :device, optional: true

  validates :semantic_key, :semantic_version, :observed_at, :normalized_at,
    :normalizer_key, :normalizer_version, :source_record_id, presence: true
  validates :quality_state, inclusion: { in: QUALITY_STATES }
  validates :public_id, presence: true, uniqueness: { scope: :organization_id }

  before_validation :assign_public_id, on: :create

  scope :observed, -> { where(quality_state: "observed") }
  scope :missing, -> { where(quality_state: MISSING_STATES) }
  scope :for_key, ->(key) { where(semantic_key: key) }
  scope :in_window, ->(from, to) { where(observed_at: from..to) }

  # INV-2. Canonical values are evidence; reprocessing creates NEW rows under
  # a new normalizer version (HO §155), it does not rewrite history.
  def readonly?
    persisted?
  end

  def observed? = quality_state == "observed"
  def missing? = !observed?

  # STAT-002. There is deliberately no `value_or_zero`: the whole point is
  # that absence has no numeric stand-in.
  def value
    return nil unless observed?

    value_numeric || value_text || value_code
  end

  def semantic_definition
    Definitions::Registry.fetch(semantic_key, version: semantic_version)
  end

  # HO §21: provenance is not a text note. Everything a provider needs to
  # trace this value back to its source, in one place.
  def provenance
    {
      raw_envelope_id: raw_envelope_id,
      source_id: source_id,
      source_record_id: source_record_id,
      device_id: device_id,
      recording_method: recording_method,
      measurement_protocol: measurement_protocol,
      normalizer: "#{normalizer_key}@v#{normalizer_version}",
      semantic: "#{semantic_key}@v#{semantic_version}",
      observed_at: observed_at,
      source_modified_at: source_modified_at,
      ingested_at: ingested_at,
      normalized_at: normalized_at
    }
  end

  # Subject-local day, used for day-based completeness denominators
  # (SC §13–14) and required to be correct across timezone boundaries
  # (HO §121).
  def local_date
    subject.local_date(observed_at)
  end

  private

  def assign_public_id
    self.public_id ||= "obs_#{SecureRandom.alphanumeric(20).downcase}"
  end
end
