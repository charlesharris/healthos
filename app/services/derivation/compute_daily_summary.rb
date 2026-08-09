# frozen_string_literal: true

module Derivation
  # Computes and persists a daily derived signal, recording exact lineage.
  #
  # Idempotent on HO §26's identity — subject + semantic key/version + window
  # + algorithm version — enforced by the unique index, not a check-then-insert
  # (S2C-020/022).
  #
  # HO §26: "do not overwrite a derived signal used by a pinned Investigation."
  # Rather than tracking which signals are pinned, none are overwritten:
  # recomputation under a new algorithm version inserts a new row and marks
  # the previous one superseded (HO §155).
  class ComputeDailySummary
    Result = Struct.new(:derived_signal, :created, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(subject:, semantic_key:, date:, algorithm: Hypertension::DailyBloodPressureSummary,
                   summary_key: "health.vital.blood_pressure.daily_summary")
      @subject = subject
      @semantic_key = semantic_key
      @date = date
      @algorithm = algorithm
      @summary_key = summary_key
    end

    def call
      existing = find_existing
      return Result.new(derived_signal: existing, created: false) if existing

      outcome = @algorithm.new(observations: observations, semantic_key: @semantic_key).call
      persist(outcome)
    rescue ActiveRecord::RecordNotUnique
      found = find_existing
      raise if found.nil?

      Result.new(derived_signal: found, created: false)
    end

    private

    # The window is the subject's LOCAL day, not a UTC day. Completeness
    # denominators are day-based (SC §13–14) and HO §121 makes timezone
    # boundaries a required regression case — a UTC window would assign a
    # 22:00 reading in New York to the wrong day.
    def window
      zone = ActiveSupport::TimeZone[@subject.timezone]
      start = zone.parse("#{@date} 00:00:00")
      [ start, start.end_of_day ]
    end

    def observations
      from, to = window

      Observation
        .where(organization_id: @subject.organization_id, subject_id: @subject.id,
               semantic_key: @semantic_key)
        .where(observed_at: from..to)
        .order(:observed_at)
    end

    def find_existing
      from, to = window

      DerivedSignal.find_by(
        organization_id: @subject.organization_id, subject_id: @subject.id,
        semantic_key: @summary_key, semantic_version: summary_definition.version,
        window_started_at: from, window_ended_at: to,
        algorithm_version: @algorithm.version
      )
    end

    def summary_definition
      Definitions::Registry.fetch(@summary_key)
    end

    def persist(outcome)
      from, to = window
      signal = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        # Lineage first, so a derived value can never exist without the record
        # of what produced it (INV-3).
        evidence_set = EvidenceSet.record!(
          organization: @subject.organization,
          purpose: "derived_signal_inputs",
          as_of: to,
          records: outcome.inputs
        )

        signal = DerivedSignal.create!(
          organization: @subject.organization, subject: @subject,
          semantic_key: @summary_key, semantic_version: summary_definition.version,
          window_started_at: from, window_ended_at: to,
          value_numeric: outcome.value_numeric, unit: outcome.unit,
          algorithm_key: @algorithm.key, algorithm_version: @algorithm.version,
          algorithm_digest: @algorithm.digest,
          evidence_set: evidence_set,
          usable_input_count: outcome.usable_input_count,
          raw_input_count: outcome.raw_input_count,
          status: outcome.status,
          computed_at: Time.current, as_of: to
        )
      end

      Result.new(derived_signal: signal, created: true)
    end
  end
end
