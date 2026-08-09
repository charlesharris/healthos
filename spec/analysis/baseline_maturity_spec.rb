# frozen_string_literal: true

require "rails_helper"

# Epic 003-06/007/008. SC §21 (maturity), §22 (thresholds), §23 (affected
# minimums); STAT-015, STAT-016, STAT-017, STAT-018, STAT-044.
RSpec.describe Analysis::BaselineMaturity, type: :model do
  # Asserted against the CONTRACT's numbers, not against whatever the config
  # happens to say. If someone edits the governed file these fail — which is
  # the point: STAT-044 requires a version bump and human review, not a quiet
  # edit that a green suite would bless.
  describe "SC §22 thresholds are transcribed correctly" do
    let(:config) { Analysis::StatisticalConfig.instance }

    it "matches the contract's baseline minimums (STAT-016)" do
      expect(config.baseline("minimum_usable_units")).to eq(10)
      expect(config.baseline("minimum_calendar_span_days")).to eq(14)
    end

    it "matches the contract's baseline targets (STAT-017)" do
      expect(config.baseline("target_usable_units")).to eq(21)
      expect(config.baseline("target_calendar_span_days")).to eq(28)
    end

    it "matches the contract's affected-window minimums (STAT-018)" do
      expect(config.affected_window("minimum_usable_units")).to eq(5)
      expect(config.affected_window("minimum_calendar_span_days")).to eq(7)
    end
  end

  describe "SC §21 maturity rule" do
    def maturity(units, span) = described_class.call(usable_units: units, calendar_span_days: span)

    it "is immature below the minimum" do
      expect(maturity(9, 20)).to eq("immature")
    end

    it "is partial at the minimum" do
      expect(maturity(10, 14)).to eq("partial")
    end

    it "is partial between minimum and target" do
      expect(maturity(15, 20)).to eq("partial")
    end

    it "is mature at the target" do
      expect(maturity(21, 28)).to eq("mature")
    end

    # Ten readings crammed into three days is not a fortnight's baseline.
    # SC §21 stores both units and span precisely so a burst of measurement
    # cannot pass for sustained history.
    it "takes the weaker of units and span" do
      expect(maturity(30, 10)).to eq("immature")
      expect(maturity(30, 20)).to eq("partial")
      expect(maturity(12, 60)).to eq("partial")
    end
  end

  describe "SC §23 affected-window sufficiency" do
    it "requires both the unit and span minimums" do
      expect(described_class.affected_window_sufficient?(usable_units: 5, calendar_span_days: 7)).to be(true)
      expect(described_class.affected_window_sufficient?(usable_units: 4, calendar_span_days: 7)).to be(false)
      expect(described_class.affected_window_sufficient?(usable_units: 5, calendar_span_days: 6)).to be(false)
    end

    # An affected window is not a baseline. It has no maturity — it either
    # clears the minimum or the comparison is refused for insufficient
    # longitudinal evidence (STAT-018).
    it "does not report maturity for an affected window" do
      expect(described_class).not_to respond_to(:affected_window_maturity)
    end
  end

  describe "STAT-044 governance" do
    it "hard-codes no threshold in the resolver" do
      code = Rails.root.join("app/services/analysis/baseline_maturity.rb").read
        .lines.reject { |l| l.strip.start_with?("#") }.join

      # Every number must come from config. A bare integer here would be a
      # governed value living where nobody reviews it.
      expect(code).not_to match(/\b(10|14|21|28)\b/)
    end

    it "exposes a digest so artifacts can record which config they used" do
      expect(Analysis::StatisticalConfig.instance.digest).to match(/\A[0-9a-f]{64}\z/)
    end

    it "raises rather than defaulting when a setting is missing" do
      expect { Analysis::StatisticalConfig.instance.baseline("nonexistent") }
        .to raise_error(Analysis::StatisticalConfig::UnknownSetting)
    end

    it "freezes the configuration so nothing can mutate a threshold at runtime" do
      expect(Analysis::StatisticalConfig.instance.fetch("baseline_thresholds", "baseline")).to be_frozen
    end
  end
end
