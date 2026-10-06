require "rails_helper"

RSpec.describe CostarWeb do
  def member(id, name, episodes, characters = [ "Role" ])
    TmdbClient::AggregateCastMember.new(
      person_id: id, name: name, photo_url: nil, total_episodes: episodes,
      roles: characters.map { |c| { character: c, episode_count: episodes } }
    )
  end

  let(:tmdb) { instance_double(TmdbClient) }
  let(:credits) do
    {
      1 => [ member(10, "Baranski", 100, [ "Diane" ]), member(11, "Lane", 9), member(12, "Solo A", 50) ],
      2 => [ member(10, "Baranski", 44), member(11, "Lane", 16), member(13, "Solo B", 80) ],
      3 => [ member(11, "Lane", 4), member(10, "Baranski", 1) ]
    }
  end

  before do
    credits.each_key do |id|
      allow(tmdb).to receive(:tv).with(id).and_return({ name: "Show #{id}", seasons: [] })
      allow(tmdb).to receive(:tv_aggregate_credits).with(id).and_return(credits[id])
    end
  end

  subject(:web) { described_class.new(tmdb: tmdb) }

  it "reports the chosen series" do
    expect(web.call([ 1, 2 ]).series).to eq([ { id: 1, title: "Show 1" }, { id: 2, title: "Show 2" } ])
  end

  it "keeps only people in at least two series and drops single-series people" do
    names = web.call([ 1, 2 ]).people.map { |p| p[:name] }

    expect(names).to eq(%w[Baranski Lane])
  end

  it "sums only the episodes from matched series" do
    baranski = web.call([ 1, 2 ]).people.first

    expect(baranski[:total_episodes]).to eq(144)
    expect(baranski[:shows]).to eq([
      { series_id: 1, episodes: 100, characters: [ "Diane" ] },
      { series_id: 2, episodes: 44, characters: [ "Role" ] }
    ])
  end

  it "scales size by sqrt of episodes, with the biggest at 1.0" do
    baranski, lane = web.call([ 1, 2 ]).people

    expect(baranski[:size]).to eq(1.0)
    expect(lane[:size]).to be_within(1e-9).of(Math.sqrt(25) / Math.sqrt(144))
  end

  it "sorts by total episodes descending" do
    totals = web.call([ 1, 2, 3 ]).people.map { |p| p[:total_episodes] }

    expect(totals).to eq(totals.sort.reverse)
  end

  it "honours min_series" do
    people = described_class.new(tmdb: tmdb, min_series: 3).call([ 1, 2, 3 ]).people

    expect(people.map { |p| p[:name] }).to eq(%w[Baranski Lane])
    expect(described_class.new(tmdb: tmdb, min_series: 3).call([ 1, 2 ]).people).to eq([])
  end

  it "returns no people when there is no overlap" do
    allow(tmdb).to receive(:tv_aggregate_credits).with(2).and_return([ member(99, "Other", 3) ])

    expect(web.call([ 1, 2 ]).people).to eq([])
  end
end
