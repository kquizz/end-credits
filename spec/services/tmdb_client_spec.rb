require "rails_helper"

RSpec.describe TmdbClient do
  subject(:client) { described_class.new(token: "eyJ-test") }

  def stub_tmdb(path, body, **opts)
    stub = stub_request(:get, "https://api.themoviedb.org/3#{path}")
    stub = stub.with(**opts) if opts.any?
    stub.to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "sends the bearer token" do
    stub_tmdb("/search/multi", { results: [] }, headers: { "Authorization" => "Bearer eyJ-test" },
              query: { "query" => "x" })
    expect(client.search("x")).to eq([])
  end

  it "sends a v3 api key as a query param instead of a header" do
    stub = stub_request(:get, "https://api.themoviedb.org/3/search/multi")
      .with(query: { "query" => "x", "api_key" => "abc123" })
      .to_return(status: 200, body: { results: [] }.to_json)

    described_class.new(token: "abc123").search("x")

    expect(stub).to have_been_requested
    expect(a_request(:get, /themoviedb/).with(headers: { "Authorization" => /./ })).not_to have_been_made
  end

  it "does not put the api key in the cache key" do
    cache = ActiveSupport::Cache::MemoryStore.new
    stub_request(:get, /themoviedb/).to_return(status: 200, body: { results: [] }.to_json)

    described_class.new(token: "secretkey", cache: cache).search("x")

    expect(cache.instance_variable_get(:@data).keys.join).not_to include("secretkey")
  end

  describe "#search" do
    it "keeps only movies and shows" do
      stub_tmdb("/search/multi", { results: [
        { media_type: "movie", id: 1, title: "Heat", release_date: "1995-12-15", poster_path: "/h.jpg", popularity: 42.5 },
        { media_type: "tv", id: 2, name: "The Wire", first_air_date: "2002-06-02" },
        { media_type: "person", id: 3, name: "Al Pacino" }
      ] }, query: { "query" => "heat" })

      results = client.search("heat")

      expect(results.map(&:title)).to eq([ "Heat", "The Wire" ])
      expect(results.first.year).to eq(1995)
      expect(results.first.popularity).to eq(42.5)
      expect(results.first.poster_url).to eq("https://image.tmdb.org/t/p/w185/h.jpg")
    end

    it "does not call the API for a blank query" do
      expect(client.search(" ")).to eq([])
      expect(a_request(:get, /themoviedb/)).not_to have_been_made
    end
  end

  describe "#search_person" do
    it "returns people with a few known-for titles" do
      stub_tmdb("/search/person", { results: [
        { id: 31, name: "Tom Hanks", profile_path: "/t.jpg",
          known_for: [ { title: "Forrest Gump" }, { name: "Band of Brothers" } ] }
      ] }, query: { "query" => "tom h" })

      person = client.search_person("tom h").first

      expect(person.id).to eq(31)
      expect(person.known_for).to eq([ "Forrest Gump", "Band of Brothers" ])
    end
  end

  describe "#episode_cast" do
    it "puts regular cast before guest stars and de-duplicates" do
      stub_tmdb("/tv/1/season/2/episode/3/credits", {
        cast: [ { id: 10, name: "A", character: "Lead" } ],
        guest_stars: [ { id: 11, name: "B", character: "Cameo" }, { id: 10, name: "A", character: "Dupe" } ]
      })

      cast = client.episode_cast(1, 2, 3)

      expect(cast.map(&:name)).to eq(%w[A B])
      expect(cast.first.character).to eq("Lead")
    end
  end

  describe "#person_credits" do
    it "maps movie and tv credits with character and genres" do
      stub_tmdb("/person/5/combined_credits", { cast: [
        { media_type: "movie", id: 1, title: "Heat", release_date: "1995-12-15",
          character: "Vincent", genre_ids: [ 28 ] },
        { media_type: "tv", id: 2, name: "Show", first_air_date: "2010-01-01",
          character: "Self", genre_ids: [ 10767 ] }
      ] })

      credits = client.person_credits(5)

      expect(credits.map(&:title)).to eq(%w[Heat Show])
      expect(credits.last.character).to eq("Self")
      expect(credits.last.year).to eq(2010)
    end
  end

  describe "#person_credits extras" do
    it "passes through episode count, poster and popularity" do
      stub_tmdb("/person/6/combined_credits", { cast: [
        { media_type: "tv", id: 2, name: "Show", first_air_date: "2010-01-01", character: "X",
          episode_count: 12, poster_path: "/p.jpg", popularity: 4.5 },
        { media_type: "movie", id: 3, title: "Film", release_date: "2001-01-01", character: "Y" }
      ] })

      show, film = client.person_credits(6)

      expect(show).to have_attributes(episode_count: 12, poster_url: "https://image.tmdb.org/t/p/w185/p.jpg", popularity: 4.5)
      expect(film).to have_attributes(episode_count: nil, poster_url: nil)
    end
  end

  describe "#people_credits" do
    it "fans out and gives nil for a person TMDb fails on" do
      stub_tmdb("/person/7/combined_credits", { cast: [ { media_type: "movie", id: 1, title: "A" } ] })
      stub_request(:get, "https://api.themoviedb.org/3/person/8/combined_credits").to_return(status: 500)

      result = client.people_credits([ 7, 8, 7 ])

      expect(result.keys).to eq([ 7, 8 ])
      expect(result[7].map(&:title)).to eq([ "A" ])
      expect(result[8]).to be_nil
    end
  end

  describe "#discover_ids" do
    it "walks every page of a discover query" do
      stub_tmdb("/discover/movie", { results: [ { id: 1 }, { id: 2 } ], total_pages: 2 }, query: { "with_companies" => "420", "page" => "1" })
      stub_tmdb("/discover/movie", { results: [ { id: 3 } ], total_pages: 2 }, query: { "with_companies" => "420", "page" => "2" })

      expect(client.discover_ids("movie", with_companies: 420)).to eq([ 1, 2, 3 ])
    end
  end

  describe "#tv" do
    it "lists seasons without specials" do
      stub_tmdb("/tv/9", { name: "Show", seasons: [
        { season_number: 0, name: "Specials", episode_count: 2 },
        { season_number: 1, name: "Season 1", episode_count: 8 }
      ] })

      expect(client.tv(9)[:seasons].map(&:number)).to eq([ 1 ])
    end
  end
  describe "#movie" do
    it "returns the title and year" do
      stub_tmdb("/movie/949", { title: "Heat", release_date: "1995-12-15" })

      expect(client.movie(949)).to have_attributes(name: "Heat", date: Date.new(1995, 12, 15), year: 1995)
    end

    it "raises NotFound on a 404" do
      stub_request(:get, "https://api.themoviedb.org/3/movie/0").to_return(status: 404, body: "{}")

      expect { client.movie(0) }.to raise_error(TmdbClient::NotFound)
    end

    it "raises Error on other failures" do
      stub_request(:get, "https://api.themoviedb.org/3/movie/1").to_return(status: 500, body: "{}")

      expect { client.movie(1) }.to raise_error(TmdbClient::Error)
    end
  end

  describe "#season_episodes" do
    it "parses air dates and tolerates a missing one" do
      stub_tmdb("/tv/9/season/1", { episodes: [
        { episode_number: 1, name: "Pilot", air_date: "2020-03-04" },
        { episode_number: 2, name: "Unaired", air_date: nil }
      ] })

      expect(client.season_episodes(9, 1).map(&:date)).to eq([ Date.new(2020, 3, 4), nil ])
    end
  end

  describe "#people_details" do
    it "returns imdb id and birth/death dates, treating blanks and bad dates as nil" do
      stub_tmdb("/person/1", { imdb_id: "nm1", birthday: "1965-08-11", deathday: "2019-01-02" })
      stub_tmdb("/person/2", { imdb_id: "", birthday: "not a date", deathday: nil })

      details = client.people_details([ 1, 2 ])

      expect(details[1]).to have_attributes(imdb_id: "nm1", birthday: Date.new(1965, 8, 11), deathday: Date.new(2019, 1, 2))
      expect(details[2]).to have_attributes(imdb_id: nil, birthday: nil, deathday: nil)
    end
  end

  describe "#person_imdb_ids" do
    it "looks up every person and keys the result by person id" do
      stub_tmdb("/person/1", { imdb_id: "nm1" })
      stub_tmdb("/person/2", { imdb_id: "" })
      stub_tmdb("/person/3", { imdb_id: "nm3" })

      expect(client.person_imdb_ids([ 1, 2, 3, 1 ])).to eq(1 => "nm1", 2 => nil, 3 => "nm3")
    end

    it "gives nil for a person TMDb fails on without losing the rest" do
      stub_tmdb("/person/1", { imdb_id: "nm1" })
      stub_request(:get, "https://api.themoviedb.org/3/person/2").to_return(status: 500, body: "{}")

      expect(client.person_imdb_ids([ 1, 2 ])).to eq(1 => "nm1", 2 => nil)
    end

    it "returns {} for no ids" do
      expect(client.person_imdb_ids([])).to eq({})
    end
  end

  describe "#tv_aggregate_credits" do
    let(:body) do
      { cast: [ { id: 5, name: "Christine Baranski", profile_path: "/c.jpg", total_episode_count: 189,
                  roles: [ { character: "Diane Lockhart", episode_count: 156 }, { character: "Diane", episode_count: 33 } ] },
                { id: 6, name: "No Photo", profile_path: nil, total_episode_count: 1, roles: [] } ] }
    end

    it "parses each cast member with episode counts and roles" do
      stub_tmdb("/tv/1435/aggregate_credits", body)

      first, second = client.tv_aggregate_credits(1435)

      expect(first.person_id).to eq(5)
      expect(first.total_episodes).to eq(189)
      expect(first.photo_url).to eq("https://image.tmdb.org/t/p/w185/c.jpg")
      expect(first.roles).to eq([ { character: "Diane Lockhart", episode_count: 156 }, { character: "Diane", episode_count: 33 } ])
      expect(second.photo_url).to be_nil
    end

    it "caches the response" do
      cache = ActiveSupport::Cache::MemoryStore.new
      stub = stub_tmdb("/tv/1435/aggregate_credits", body)
      cached = described_class.new(token: "eyJ-test", cache: cache)

      2.times { cached.tv_aggregate_credits(1435) }

      expect(stub).to have_been_requested.once
    end
  end
end
