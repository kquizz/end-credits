require "rails_helper"

RSpec.describe WatchNext do
  let(:tmdb) { instance_double(TmdbClient) }

  def credit(id, title, media_type: "tv", character: "Role", episodes: 1, year: 2010, popularity: 1.0, genre_ids: [])
    TmdbClient::Credit.new(media_type: media_type, id: id, title: title, year: year, character: character,
                           genre_ids: genre_ids, episode_count: episodes, popularity: popularity, poster_url: "p#{id}")
  end

  def run(credits, series_ids: [], **opts)
    allow(tmdb).to receive(:people_credits) { |ids| credits.slice(*ids) }
    described_class.new(tmdb: tmdb, **opts).call(credits.keys, series_ids: series_ids)
  end

  it "keeps titles with at least two members and drops single-member ones" do
    result = run({ 1 => [ credit(100, "Shared"), credit(101, "Only Ann") ], 2 => [ credit(100, "Shared") ] })

    expect(result.titles.map { |t| t[:title] }).to eq([ "Shared" ])
    expect(result.titles.first).to include(member_count: 2, person_ids: [ 1, 2 ], poster_url: "p100")
  end

  it "excludes the selected series but not a movie sharing its id" do
    result = run({ 1 => [ credit(5, "Selected"), credit(5, "Movie five", media_type: "movie") ],
                   2 => [ credit(5, "Selected"), credit(5, "Movie five", media_type: "movie") ] }, series_ids: [ 5 ])

    expect(result.titles.map { |t| t[:title] }).to eq([ "Movie five" ])
  end

  it "counts a person once per title even with duplicate credits" do
    result = run({ 1 => [ credit(100, "Dup"), credit(100, "Dup", character: "Other") ], 2 => [ credit(101, "Else") ] })

    expect(result.titles).to be_empty
  end

  it "ranks by member count, then total episodes, then popularity, then recency" do
    credits = {
      1 => [ credit(1, "Three", episodes: 1), credit(2, "TwoManyEps", episodes: 50), credit(3, "TwoFewEps", episodes: 2),
             credit(4, "PopA", popularity: 9.0), credit(5, "PopB", popularity: 1.0) ],
      2 => [ credit(1, "Three"), credit(2, "TwoManyEps", episodes: 50), credit(3, "TwoFewEps", episodes: 2),
             credit(4, "PopA", popularity: 9.0), credit(5, "PopB", popularity: 1.0) ],
      3 => [ credit(1, "Three") ]
    }

    expect(run(credits).titles.map { |t| t[:title] }).to eq(%w[Three TwoManyEps TwoFewEps PopA PopB])
  end

  it "sums episode counts across members and ignores nil for movies" do
    result = run({ 1 => [ credit(1, "Show", episodes: 10), credit(2, "Film", media_type: "movie", episodes: nil) ],
                   2 => [ credit(1, "Show", episodes: 5), credit(2, "Film", media_type: "movie", episodes: nil) ] })

    expect(result.titles.to_h { |t| [ t[:title], t[:total_episodes] ] }).to eq("Show" => 15, "Film" => 0)
  end

  it "caps the list" do
    stub_const("WatchNext::LIMIT", 2)
    list = (1..5).map { |i| credit(i, "T#{i}") }

    expect(run({ 1 => list, 2 => list }).titles.size).to eq(2)
  end

  it "only looks up the first MAX_PEOPLE people" do
    stub_const("WatchNext::MAX_PEOPLE", 2)
    allow(tmdb).to receive(:people_credits) { |ids| ids.index_with { [] } }

    described_class.new(tmdb: tmdb).call([ 1, 2, 3 ])

    expect(tmdb).to have_received(:people_credits).with([ 1, 2 ])
  end

  describe "filters" do
    let(:credits) do
      {
        1 => [ credit(1, "Talk", character: "Self"), credit(2, "Cartoon", character: "Bob (voice)"),
               credit(3, "Hero Movie", media_type: "movie"), credit(4, "Drama") ],
        2 => [ credit(1, "Talk", character: "Himself"), credit(2, "Cartoon", character: "Al (voice)"),
               credit(3, "Hero Movie", media_type: "movie"), credit(4, "Drama") ]
      }
    end

    def titles(result) = result.titles.map { |t| t[:title] }

    it "skips self and voice credits by default" do
      expect(titles(run(credits))).to contain_exactly("Hero Movie", "Drama")
    end

    it "can keep them" do
      expect(titles(run(credits, skip_self: false, skip_voice: false))).to contain_exactly("Talk", "Cartoon", "Hero Movie", "Drama")
    end

    it "skips Marvel titles only when asked" do
      allow(MarvelTitles).to receive(:new).and_return(instance_double(MarvelTitles, keys: Set["movie:3"]))

      expect(titles(run(credits, skip_marvel: true))).to eq([ "Drama" ])
      expect(titles(run(credits))).to include("Hero Movie")
    end
  end

  it "reports people whose lookup failed, and raises if every lookup failed" do
    allow(tmdb).to receive(:people_credits).and_return(1 => [ credit(1, "X") ], 2 => nil)
    result = described_class.new(tmdb: tmdb).call([ 1, 2 ])
    expect(result).to have_attributes(people_checked: 1, people_skipped: 1)

    allow(tmdb).to receive(:people_credits).and_return(1 => nil, 2 => nil)
    expect { described_class.new(tmdb: tmdb).call([ 1, 2 ]) }.to raise_error(TmdbClient::Error)
  end
end
