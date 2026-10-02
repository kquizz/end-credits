require "rails_helper"

RSpec.describe AgeLookup do
  let(:on) { Date.new(2000, 6, 1) }
  let(:cast) do
    (1..5).map { |i| TmdbClient::CastMember.new(person_id: i, name: "P#{i}", character: "C#{i}") }
  end
  let(:details) do
    {
      1 => TmdbClient::PersonDetails.new(birthday: Date.new(1980, 1, 1)),
      2 => TmdbClient::PersonDetails.new(birthday: Date.new(1940, 5, 1), deathday: Date.new(2010, 3, 1)),
      3 => TmdbClient::PersonDetails.new(birthday: Date.new(1930, 1, 1), deathday: Date.new(1990, 1, 1)),
      4 => TmdbClient::PersonDetails.new(birthday: nil),
      5 => TmdbClient::PersonDetails.new(birthday: Date.new(2005, 1, 1)) # born after the premiere: bad data
    }
  end
  let(:tmdb) { instance_double(TmdbClient, people_details: details) }

  subject(:rows) { described_class.new(tmdb: tmdb).call(cast, on: on) }

  it "works out ages on the premiere date" do
    expect(rows[0].age.years).to eq(20)
    expect(rows[0]).to be_known_age
  end

  it "keeps a living-then, since-deceased person's age and records the death year" do
    expect(rows[1].age.years).to eq(60)
    expect(rows[1].age).to be_deceased
    expect(rows[1]).not_to be_posthumous
  end

  it "flags people who died before the premiere instead of giving them an age" do
    expect(rows[2]).to be_posthumous
    expect(rows[2]).not_to be_known_age
  end

  it "treats a missing birthday as unknown" do
    expect(rows[3]).to be_unknown
  end

  it "treats a birthday after the premiere as unknown rather than a negative age" do
    expect(rows[4]).to be_unknown
  end

  it "treats everyone as unknown when there is no premiere date" do
    rows = described_class.new(tmdb: tmdb).call(cast, on: nil)

    expect(rows).to all(be_unknown)
  end

  it "treats a person TMDb failed on as unknown" do
    allow(tmdb).to receive(:people_details).and_return(1 => nil)

    expect(described_class.new(tmdb: tmdb).call(cast.first(1), on: on).first).to be_unknown
  end
end
