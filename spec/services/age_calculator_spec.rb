require "rails_helper"

RSpec.describe AgeCalculator do
  describe ".age_on" do
    it "computes age in whole years as of the target date" do
      result = described_class.age_on(born: Date.new(1980, 1, 1), on: Date.new(2000, 6, 1))
      expect(result.years).to eq(20)
      expect(result.unknown?).to be(false)
    end

    it "does not count a birthday that has not yet occurred on the target date" do
      result = described_class.age_on(born: Date.new(1980, 12, 31), on: Date.new(2000, 6, 1))
      expect(result.years).to eq(19)
    end

    it "counts a birthday that falls exactly on the target date" do
      result = described_class.age_on(born: Date.new(1980, 6, 1), on: Date.new(2000, 6, 1))
      expect(result.years).to eq(20)
    end

    it "handles a Feb 29 birthday against a non-leap target year" do
      result = described_class.age_on(born: Date.new(2000, 2, 29), on: Date.new(2019, 2, 28))
      expect(result.years).to eq(18)
    end

    it "returns an unknown result when the birthday is nil" do
      result = described_class.age_on(born: nil, on: Date.new(2000, 6, 1))
      expect(result.unknown?).to be(true)
      expect(result.years).to be_nil
    end

    it "flags a deceased person and still reports age on the target date" do
      result = described_class.age_on(
        born: Date.new(1940, 5, 1), on: Date.new(1990, 1, 1), died: Date.new(2010, 3, 1)
      )
      expect(result.years).to eq(49)
      expect(result.deceased?).to be(true)
      expect(result.death_year).to eq(2010)
    end
  end
end
