require "rails_helper"

RSpec.describe AwardClassifier do
  def classify(cats) = described_class.call(cats)

  it "detects all four families for a real EGOT winner (Viola Davis categories)" do
    cats = [
      "Category:Best Supporting Actress Academy Award winners",
      "Category:Grammy Award winners",
      "Category:Primetime Emmy Award winners",
      "Category:Tony Award winners",
      "Category:Best Supporting Actress BAFTA Award winners",
      "Category:Drama Desk Award winners"
    ]
    status = classify(cats)
    expect(status.egot?).to be(true)
    expect(status.score).to eq(4)
  end

  it "detects an Oscar from the '…Award–winning' songwriter form (John Legend)" do
    status = classify([ "Category:Best Original Song Academy Award–winning songwriters" ])
    expect(status.won?(:oscar)).to be(true)
    expect(status.won?(:grammy)).to be(false)
  end

  it "does not treat BAFTA as an Oscar" do
    status = classify([ "Category:Best Actress BAFTA Award winners" ])
    expect(status.won?(:oscar)).to be(false)
  end

  it "does not treat an Academy of Country Music award as an Oscar" do
    status = classify([ "Category:Academy of Country Music Award winners" ])
    expect(status.won?(:oscar)).to be(false)
  end

  it "ignores nominee categories" do
    status = classify([ "Category:Grammy Award nominees" ])
    expect(status.won?(:grammy)).to be(false)
  end

  it "collects the specific win labels with the Category: prefix stripped" do
    status = classify([
      "Category:Grammy Award winners",
      "Category:Best New Artist Grammy Award winners"
    ])
    expect(status.wins(:grammy)).to contain_exactly(
      "Grammy Award winners", "Best New Artist Grammy Award winners"
    )
  end

  it "returns all-false for a person with no EGOT categories" do
    status = classify([ "Category:American film actors", "Category:Living people" ])
    expect(status.score).to eq(0)
  end
end
