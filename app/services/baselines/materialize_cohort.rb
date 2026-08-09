# frozen_string_literal: true

module Baselines
  # Materializes a baseline for every subject in an organization that has data
  # for a measure (SC §66's precondition).
  #
  # SC §66: "Default cohort analysis unit: subject, not individual
  # observations. Subject-level features are computed first… This prevents
  # patients with dense telemetry from dominating the sample."
  #
  # "Computed first" is the operative phrase and the reason this exists as a
  # batch rather than a read: a cohort comparison that built 47 baselines
  # inside a request would be answering a statistical question during page
  # render, and would be slow enough that somebody would eventually replace it
  # with a cheaper approximation still labelled "baseline".
  #
  # Retry-safe by construction — Materialize is idempotent on artifact
  # identity, so a job that dies halfway and runs again produces no
  # duplicates and redoes only what it must (HO §98).
  class MaterializeCohort
    Result = Struct.new(:created, :existing, :skipped, :as_of, keyword_init: true) do
      def total = created + existing
    end

    def self.call(...) = new(...).call

    def initialize(organization:, semantic_key:, as_of:, ends_at: nil)
      @organization = organization
      @semantic_key = semantic_key
      @as_of = as_of
      @ends_at = ends_at
    end

    def call
      created = 0
      existing = 0
      skipped = 0

      subjects_with_data.find_each do |subject|
        outcome = Materialize.call(
          subject: subject, semantic_key: @semantic_key, as_of: @as_of, ends_at: @ends_at
        )
        outcome.created? ? created += 1 : existing += 1
      rescue ActiveRecord::RecordInvalid => e
        # One subject's baseline failing must not cost the other forty-six.
        # Counted and logged rather than swallowed: a cohort that silently
        # shrank would make every share computed from it wrong by an unknown
        # amount (S2C-019's rule applied to a batch — a failure is a state,
        # not an absence).
        skipped += 1
        Rails.logger.warn(
          "[baselines] subject_id=#{subject.id} semantic_key=#{@semantic_key} skipped: #{e.class}"
        )
      end

      Result.new(created: created, existing: existing, skipped: skipped, as_of: @as_of)
    end

    private

    # Only subjects who actually have observed readings for this measure. A
    # baseline over nothing is immature by definition, and materializing rows
    # for subjects who never enrolled in the measure would dilute every cohort
    # denominator computed from the table.
    def subjects_with_data
      Subject.where(organization_id: @organization.id).where(
        id: Observation.where(organization_id: @organization.id,
                              semantic_key: @semantic_key, quality_state: "observed")
                       .select(:subject_id)
      )
    end
  end
end
