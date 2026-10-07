require "rails_helper"

RSpec.describe TargetList do
  describe "the shipped list" do
    subject(:list) { described_class.new }

    it "has about forty people across all three tiers with unique ids" do
      expect(list.all.size).to be_between(36, 50)
      expect(list.all.map(&:tier).uniq).to match_array(TargetList::TIERS)
      expect(list.all.map(&:id).uniq.size).to eq(list.all.size)
    end
  end

  describe "with a fixture file" do
    let(:file) do
      Tempfile.new([ "targets", ".yml" ]).tap do |f|
        f.write({ "easy" => [ { "name" => "A", "id" => 1 }, { "name" => "B", "id" => 2 }, { "name" => "C", "id" => 3 } ],
                  "hard" => [ { "name" => "D", "id" => 4 }, { "name" => "E", "id" => 5 } ] }.to_yaml)
        f.flush
      end
    end
    let(:list) { described_class.new(path: file.path) }

    it "finds a person by id, string or integer" do
      expect(list.find("4")).to have_attributes(name: "D", tier: "hard")
      expect(list.find(99)).to be_nil
    end

    it "draws two different people from the tier" do
      20.times do
        pair = list.random_pair(tier: "hard")
        expect(pair.map(&:id)).to match_array([ 4, 5 ])
      end
    end

    it "mixes tiers when none is given and falls back when the tier is unknown or too small" do
      expect(list.random_pair.map(&:id).uniq.size).to eq(2)
      expect(list.random_pair(tier: "nope").map(&:id).uniq.size).to eq(2)
    end
  end
end
