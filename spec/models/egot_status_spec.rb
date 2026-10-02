require "rails_helper"

RSpec.describe EgotStatus do
  def status(overrides = {})
    base = { emmy: { won: false, wins: [] }, grammy: { won: false, wins: [] },
             oscar: { won: false, wins: [] }, tony: { won: false, wins: [] } }
    described_class.new(base.merge(overrides))
  end

  it "counts the number of award families won" do
    s = status(emmy: { won: true, wins: [ "a" ] }, oscar: { won: true, wins: [ "b" ] })
    expect(s.score).to eq(2)
  end

  it "is an EGOT only when all four are won" do
    all = { emmy: { won: true, wins: [] }, grammy: { won: true, wins: [] },
            oscar: { won: true, wins: [] }, tony: { won: true, wins: [] } }
    expect(described_class.new(all).egot?).to be(true)
    expect(status(emmy: { won: true, wins: [] }).egot?).to be(false)
  end

  it "lists the labels of the missing families" do
    s = status(emmy: { won: true, wins: [] }, grammy: { won: true, wins: [] },
               oscar: { won: true, wins: [] })
    expect(s.missing_labels).to eq([ "Tony" ])
  end

  it "exposes won? and wins per family" do
    s = status(grammy: { won: true, wins: [ "Best New Artist" ] })
    expect(s.won?(:grammy)).to be(true)
    expect(s.wins(:grammy)).to eq([ "Best New Artist" ])
    expect(s.won?(:tony)).to be(false)
  end
end
