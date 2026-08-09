# frozen_string_literal: true

require "rails_helper"

# Structural guards for the Ops surfaces.
#
# These assert on source text rather than behaviour, deliberately. The
# behavioural specs prove today's controllers are correct; these fail the
# build the day someone adds a controller that takes the shortcut, which is
# exactly when the reviewer is least likely to notice.
RSpec.describe "Ops controller invariants", type: :model do
  def ops_controller_sources
    Rails.root.glob("app/controllers/ops/**/*.rb").index_with { |path| code_only(path.read) }
  end

  def ops_view_sources
    Rails.root.glob("app/views/ops/**/*.erb").index_with { |path| code_only(path.read) }
  end

  # Comments explain the invariants and therefore quote the words the
  # invariants forbid. Guards that grep source must read the code, not the
  # commentary, or the explanation becomes the violation.
  def code_only(source)
    source
      .gsub(/<%#.*?%>/m, "")
      .lines
      .reject { |line| line.strip.start_with?("#") }
      .join
  end

  # S2C-013. A controller that writes Case state directly produces a Case
  # whose timeline does not explain how it got there — and the timeline is the
  # authoritative workflow history (HO §39). Every state change goes through
  # Cases::Transition; every assignment through Cases::Assign.
  describe "S2C-013 no direct mutation in app/controllers/ops" do
    let(:forbidden_writes) do
      /\.(update!?|update_column|update_columns|update_attribute|save!?|destroy!?|delete)\b/
    end

    it "contains no direct persistence call" do
      offenders = ops_controller_sources.flat_map do |path, source|
        source.lines.filter_map do |line|
          "#{path.relative_path_from(Rails.root)}: #{line.strip}" if line.match?(forbidden_writes)
        end
      end

      expect(offenders).to be_empty,
        "Ops controllers must not mutate records directly (S2C-013). " \
        "Route state through Cases::Transition and assignment through " \
        "Cases::Assign:\n#{offenders.join("\n")}"
    end

    it "changes state only by calling Cases::Transition" do
      source = ops_controller_sources.values.join

      expect(source).to include("Cases::Transition.call")
      expect(source).not_to match(/status\s*[:=]\s*["']/)
    end
  end

  # S2C-023 and STAT-024. Ordering is explainable SQL over policy columns.
  # A numeric importance score is forbidden in the queue as firmly as it is in
  # the analysis (CLAUDE.md: no "AI Risk Score: 87").
  describe "S2C-023 no opaque ranking" do
    it "never orders by evidence strength" do
      Ops::CaseQuery::SORTS.each_key do |sort|
        columns = Ops::CaseQuery::SORTS.fetch(sort)[:columns].join(" ")

        expect(columns).not_to include("evidence_level")
      end
    end

    it "gives every offered sort a human explanation" do
      Ops::CaseQuery::SORTS.each_value do |definition|
        expect(definition[:explanation]).to be_present
        expect(definition[:label]).to be_present
      end
    end

    it "computes no score in the queue query or its views" do
      queries = Rails.root.glob("app/queries/ops/**/*.rb").index_with { |path| code_only(path.read) }
      sources = queries.merge(ops_view_sources)

      sources.each do |path, source|
        expect(source).not_to match(/\bscore\b/i), "#{path} introduces a score"
      end
    end
  end

  # HO §84: subject identity is secondary and opaque. The queue and Quick
  # Review render a public handle; reading a name is a separate, audited act.
  describe "HO §84 no identity fields in Ops views" do
    it "renders no SubjectIdentity attribute" do
      identity_fields = %w[first_name last_name display_name date_of_birth contact_email contact_phone]

      ops_view_sources.each do |path, source|
        identity_fields.each do |field|
          expect(source).not_to include(field), "#{path} renders subject #{field}"
        end
      end
    end
  end

  # INV-31. Every tenant-facing read is a Tenanted::Query subclass with an
  # explicit organization, so tenancy is visible in the signature rather than
  # inherited from whatever happened to be on the current thread.
  describe "INV-31 reads go through tenanted queries" do
    it "declares every ops query as a Tenanted::Query" do
      Rails.root.glob("app/queries/ops/*.rb").each do |path|
        klass = "Ops::#{File.basename(path, '.rb').camelize}".constantize

        expect(klass.ancestors).to include(Tenanted::Query), "#{klass} is not tenanted"
      end
    end

    it "uses no unscoped model finder in an ops controller" do
      ops_controller_sources.each do |path, source|
        expect(source).not_to match(/Cases::CaseRecord\.(find|where|all|first|last)\b/),
          "#{path} reads Cases directly instead of through Ops::CaseDetailQuery/Ops::CaseQuery"
      end
    end
  end
end
