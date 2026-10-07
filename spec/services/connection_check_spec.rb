require "rails_helper"

RSpec.describe ConnectionCheck do
  let(:tmdb) { instance_double(TmdbClient) }

  def credit(id, title, media_type: "movie", character: "Role", year: 1995, genre_ids: [], popularity: 1.0)
    TmdbClient::Credit.new(media_type: media_type, id: id, title: title, year: year, character: character,
                           genre_ids: genre_ids, popularity: popularity, poster_url: "p#{id}")
  end

  def check(credits, marvel_ids: nil, **rules)
    allow(tmdb).to receive(:person_credits) { |id| credits.fetch(id) }
    described_class.new(client: tmdb, marvel_ids: marvel_ids).call(1, 2, rules)
  end

  it "returns the shared title with its details" do
    titles = check({ 1 => [ credit(10, "Heat"), credit(11, "Solo") ], 2 => [ credit(10, "Heat"), credit(12, "Other") ] })

    expect(titles).to eq([ { id: 10, title: "Heat", year: 1995, media_type: "movie", poster_url: "p10" } ])
  end

  it "returns nothing when the credits do not overlap" do
    expect(check({ 1 => [ credit(10, "A") ], 2 => [ credit(11, "B") ] })).to eq([])
  end

  it "does not confuse a movie and a show with the same id" do
    expect(check({ 1 => [ credit(10, "Movie") ], 2 => [ credit(10, "Show", media_type: "tv") ] })).to eq([])
  end

  it "ignores Self credits by default but counts them when the rule is off" do
    credits = { 1 => [ credit(10, "Late Show", media_type: "tv", character: "Self", genre_ids: [ 10767 ]) ],
                2 => [ credit(10, "Late Show", media_type: "tv", character: "Himself") ] }

    expect(check(credits)).to eq([])
    expect(check(credits, skip_self: false).map { |t| t[:title] }).to eq([ "Late Show" ])
  end

  it "ignores voice credits by default" do
    credits = { 1 => [ credit(10, "Toon", character: "Rex (voice)") ], 2 => [ credit(10, "Toon", character: "Buzz") ] }

    expect(check(credits)).to eq([])
    expect(check(credits, skip_voice: false).size).to eq(1)
  end

  it "excludes Marvel titles when asked" do
    credits = { 1 => [ credit(10, "Avengers"), credit(11, "Heat") ], 2 => [ credit(10, "Avengers") ] }

    expect(check(credits, skip_marvel: true, marvel_ids: Set["movie:10"])).to eq([])
    expect(check(credits, skip_marvel: false, marvel_ids: Set["movie:10"]).size).to eq(1)
  end

  it "looks the Marvel titles up when none were given" do
    marvel = instance_double(MarvelTitles, keys: Set["movie:10"])
    allow(MarvelTitles).to receive(:new).with(tmdb: tmdb).and_return(marvel)

    expect(check({ 1 => [ credit(10, "Avengers") ], 2 => [ credit(10, "Avengers") ] }, skip_marvel: true)).to eq([])
  end

  it "applies movies only and the year range" do
    credits = { 1 => [ credit(10, "Show", media_type: "tv"), credit(11, "Old", year: 1970), credit(12, "New", year: 2005) ],
                2 => [ credit(10, "Show", media_type: "tv"), credit(11, "Old", year: 1970), credit(12, "New", year: 2005) ] }

    expect(check(credits, movies_only: true).map { |t| t[:title] }).to match_array(%w[Old New])
    expect(check(credits, years: 2000..2010).map { |t| t[:title] }).to eq([ "New" ])
  end

  it "lists the most popular shared title first" do
    credits = { 1 => [ credit(10, "Minor", popularity: 1), credit(11, "Major", popularity: 50) ],
                2 => [ credit(10, "Minor"), credit(11, "Major") ] }

    expect(check(credits).map { |t| t[:title] }).to eq(%w[Major Minor])
  end
end
