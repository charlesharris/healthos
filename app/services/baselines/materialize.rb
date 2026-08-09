# frozen_string_literal: true

module Baselines
  # Materializes a BaselineInstance (HO §57, SC §19–22; epic 003-07/003-08).
  #
  # `Baselines::PersonalRecent` has been able to BUILD a baseline since 003-08;
  # nothing persisted one. That was tolerable while baselines were only ever
  # needed for the subject already on screen, and stops being tolerable the
  # moment a cohort question is asked: "where does this subject sit among the
  # program's baselines" is 47 baseline builds per page load, which is not a
  # read.
  #
  # Idempotent on HO §26's identity — subject + definition + version + as_of +
  # input fingerprint — exactly like MaterializeContext, and for the same
  # reason: recomputing over identical inputs must return the existing
  # artifact rather than a second one. Analytical artifacts are immutable
  # snapshots (INV-13/14); there is no update path here, only find-or-create.
  #
  # Late data does not rewrite a baseline. It produces a NEW one at a new
  # `as_of`, and whatever points at baselines moves its pointer — the same
  # rule Contexts follow (HO §99, STAT-040/041).
  class Materialize
    Result = Struct.new(:baseline, :created, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(subject:, semantic_key:, as_of:, ends_at: nil,
                   definition_key: "personal_recent", case_record: nil)
      @subject = subject
      @semantic_key = semantic_key
      @as_of = as_of
      @ends_at = ends_at
      @definition_class = Definition.find(definition_key)
      @case_record = case_record
    end

    def call
      built = @definition_class.new(
        subject: @subject, semantic_key: @semantic_key, as_of: @as_of, ends_at: @ends_at
      ).build

      fingerprint = EvidenceSet.fingerprint_for(built.inputs)
      existing = find_existing(fingerprint)
      return Result.new(baseline: existing, created: false) if existing

      persist(built, fingerprint)
    rescue ActiveRecord::RecordNotUnique
      # Two workers materialized the same baseline concurrently. The unique
      # index is the arbiter (S2C-022: critical uniqueness in PostgreSQL, not
      # in Ruby); whichever lost simply reads what the winner wrote.
      found = find_existing(EvidenceSet.fingerprint_for(built.inputs))
      raise if found.nil?

      Result.new(baseline: found, created: false)
    end

    private

    def find_existing(fingerprint)
      Analysis::BaselineInstance.find_by(
        organization_id: @subject.organization_id, subject_id: @subject.id,
        definition_key: @definition_class.key,
        definition_version: @definition_class.version,
        as_of: @as_of, fingerprint: fingerprint
      )
    end

    def persist(built, fingerprint)
      baseline = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        # Lineage first: a baseline must never exist without the record of the
        # rows it rested on (INV-3). This is what makes a Finding built on it
        # drill down to source records.
        evidence_set = EvidenceSet.record!(
          organization: @subject.organization, purpose: "baseline_inputs",
          as_of: @as_of, records: built.inputs
        )

        baseline = Analysis::BaselineInstance.create!(
          organization_id: @subject.organization_id, subject_id: @subject.id,
          case_record: @case_record,
          definition_key: @definition_class.key,
          definition_version: @definition_class.version,
          definition_digest: @definition_class.digest,
          baseline_type: @definition_class.baseline_type,
          semantic_key: @semantic_key,
          semantic_version: semantic_version_for(@semantic_key),
          window_started_at: built.window.first, window_ended_at: built.window.last,
          as_of: @as_of,
          central_value: built.central_value,
          dispersion: built.dispersion,
          unit: built.unit,
          # SC §21's four, persisted rather than derived, so a historical
          # comparison can state what its baseline actually rested on.
          usable_units: built.usable_units,
          calendar_span_days: built.calendar_span_days,
          completeness: built.completeness,
          maturity: built.maturity,
          source_summary: built.source_summary || {},
          evidence_set: evidence_set,
          version_tuple: Analysis::VersionTuple.build(
            definition: @definition_class,
            extra: { "raw_reading_count" => built.raw_reading_count,
                     "missing_by_state" => built.missing_by_state }
          ),
          fingerprint: fingerprint
        )
      end

      Result.new(baseline: baseline, created: true)
    end

    # Pinned onto the artifact so a baseline keeps meaning what it meant when
    # the semantic definition is revised (INV-6..12).
    def semantic_version_for(key)
      Definitions::Registry.find(key)&.version || 1
    end
  end
end
