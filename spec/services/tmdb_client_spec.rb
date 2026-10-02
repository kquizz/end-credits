require "rails_helper"

RSpec.describe TmdbClient do
  subject(:client) { described_class.new(token: "t") }

  def stub_tmdb(path, body, **opts)
    stub = stub_request(:get, "https://api.themoviedb.org/3#{path}")
    stub = stub.with(**opts) if opts.any?
    stub.to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "sends the bearer token" do
    stub_tmdb("/search/multi", { results: [] }, headers: { "Authorization" => "Bearer t" },
              query: { "query" => "x" })
    expect(client.search("x")).to eq([])
  end

  describe "#search" do
    it "keeps only movies and shows" do
      stub_tmdb("/search/multi", { results: [
        { media_type: "movie", id: 1, title: "Heat", release_date: "1995-12-15", poster_path: "/h.jpg" },
        { media_type: "tv", id: 2, name: "The Wire", first_air_date: "2002-06-02" },
        { media_type: "person", id: 3, name: "Al Pacino" }
      ] }, query: { "query" => "heat" })

      results = client.search("heat")

      expect(results.map(&:title)).to eq([ "Heat", "The Wire" ])
      expect(results.first.year).to eq(1995)
      expect(results.first.poster_url).to eq("https://image.tmdb.org/t/p/w185/h.jpg")
    end

    it "does not call the API for a blank query" do
      expect(client.search(" ")).to eq([])
      expect(a_request(:get, /tmdb/)).not_to have_been_made
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

  describe "#tv" do
    it "lists seasons without specials" do
      stub_tmdb("/tv/9", { name: "Show", seasons: [
        { season_number: 0, name: "Specials", episode_count: 2 },
        { season_number: 1, name: "Season 1", episode_count: 8 }
      ] })

      expect(client.tv(9)[:seasons].map(&:number)).to eq([ 1 ])
    end
  end
end
