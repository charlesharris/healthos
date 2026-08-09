# frozen_string_literal: true

module Analysis
  # Materializes a Context and its values (HO §54, epic 003-04).
  #
  # HO §54 defines two modes:
  #
  #   operational   precomputed for Cases, cached, cohort-wide
  #   interactive   on-demand for custom investigations, short-lived
  #
  # Both use the same machinery. The difference is only whether the result is
  # persisted and pointed at by a Case — an interactive Context that computed
  # differently from an operational one would make the Workbench show
  # something the queue never saw, which is exactly the divergence PD §58
  # warns against by insisting "the same ContextDefinition machinery supports
  # both".
  #
  # Idempotent on HO §26's identity: subject + definition + version + as_of +
  # input fingerprint. Recomputing over identical inputs returns the existing
  # artifact rather than a duplicate, which is what makes the coordinator's
  # per-stage retry safe (HO §98).
  class MaterializeContext
    Result = Struct.new(:context, :created, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(subject:, window:, as_of:, definition_key: "blood_pressure_change",
                   case_record: nil, mode: :operational)
      @subject = subject
      @window = window
      @as_of = as_of
      @definition_class = ContextDefinition.find(definition_key)
      @case_record = case_record
      @mode = mode
    end

    def call
      definition = @definition_class.new(subject: @subject, window: @window, as_of: @as_of)
      materialization = definition.materialize

      fingerprint = EvidenceSet.fingerprint_for(materialization.inputs)
      existing = find_existing(fingerprint)
      return Result.new(context: existing, created: false) if existing

      persist(materialization, fingerprint)
    rescue ActiveRecord::RecordNotUnique
      found = find_existing(EvidenceSet.fingerprint_for([]))
      raise if found.nil?

      Result.new(context: found, created: false)
    end

    private

    def find_existing(fingerprint)
      Context.find_by(
        organization_id: @subject.organization_id, subject_id: @subject.id,
        definition_key: @definition_class.key, definition_version: @definition_class.version,
        as_of: @as_of, fingerprint: fingerprint
      )
    end

    def persist(materialization, fingerprint)
      context = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        # Lineage first: a Context must never exist without the record of what
        # produced it (INV-3).
        evidence_set = EvidenceSet.record!(
          organization: @subject.organization, purpose: "context_inputs",
          as_of: @as_of, records: materialization.inputs
        )

        context = Context.create!(
          organization_id: @subject.organization_id, subject_id: @subject.id,
          case_record: @case_record,
          definition_key: @definition_class.key,
          definition_version: @definition_class.version,
          definition_digest: @definition_class.digest,
          anchor_type: @case_record ? "case" : "window",
          anchor_id: @case_record&.id,
          window_started_at: @window.first, window_ended_at: @window.last,
          as_of: @as_of,
          status: materialization.status,
          data_completeness: materialization.data_completeness,
          input_evidence_set: evidence_set,
          version_tuple: VersionTuple.build(
            definition: @definition_class, extra: { "mode" => @mode.to_s }
          ),
          fingerprint: fingerprint
        )

        materialization.dimensions.each do |dimension|
          ContextValue.create!(
            organization_id: @subject.organization_id, context: context,
            dimension_key: dimension.key, dimension_version: dimension.version,
            value_numeric: dimension.value_numeric, value_text: dimension.value_text,
            value_boolean: dimension.value_boolean, value_json: dimension.value_json,
            details: dimension.details || {},
            unit: dimension.unit,
            quality_state: dimension.quality_state || "observed",
            window_started_at: dimension.window&.first, window_ended_at: dimension.window&.last,
            semantic_family: dimension.semantic_family,
            source_family: dimension.source_family,
            derivation_family: dimension.derivation_family
          )
        end
      end

      Result.new(context: context, created: true)
    end
  end
end
