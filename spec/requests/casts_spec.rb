require "rails_helper"

RSpec.describe "Cast", type: :request do
  let(:tmdb) { instance_double(TmdbClient) }
  let(:cast) do
    [
      TmdbClient::CastMember.new(person_id: 1, name: "Viola Davis", character: "Lead"),
      TmdbClient::CastMember.new(person_id: 2, name: "Some Extra", character: "Waiter")
    ]
  end

  before { allow(TmdbClient).to receive(:new).and_return(tmdb) }

  describe "GET /cast" do
    it "searches movies and shows and links each to its page" do
      allow(tmdb).to receive(:search).with("heat").and_return([
        TmdbClient::SearchResult.new(media_type: "movie", id: 949, title: "Heat", year: 1995),
        TmdbClient::SearchResult.new(media_type: "tv", id: 7, title: "Heat Show", year: 2001)
      ])

      get cast_path(q: "heat")

      expect(response.body).to include(cast_movie_path(949), cast_show_path(7), "Heat Show")
    end

    it "says so when nothing matches" do
      allow(tmdb).to receive(:search).and_return([])

      get cast_path(q: "zzzz")

      expect(response.body).to include("Nothing found")
    end

    it "renders an empty search page without calling TMDb" do
      get cast_path

      expect(response).to have_http_status(:ok)
      expect(TmdbClient).not_to have_received(:new)
    end
  end

  describe "GET /cast/movies/:id" do
    before do
      allow(tmdb).to receive(:movie).with("949").and_return(TmdbClient::Title.new(id: 949, name: "Heat", date: Date.new(1995, 12, 15)))
      allow(tmdb).to receive(:movie_cast).with("949").and_return(cast)
    end

    it "shows the cast right away with a lazy frame for the awards" do
      get cast_movie_path(949)

      expect(response.body).to include("Heat", "Viola Davis", "Waiter")
      expect(response.body).to include(%(src="#{cast_table_path(kind: "movie", id: 949).gsub("&", "&amp;")}"))
      expect(response.body).to include('loading="lazy"')
    end
  end

  describe "TV navigation" do
    let(:show) { { name: "Show", seasons: [ TmdbClient::Season.new(number: 2, name: "Season 2", episode_count: 3) ] } }
    let(:episodes) { [ TmdbClient::Episode.new(number: 3, name: "The One", date: Date.new(2020, 1, 2)) ] }

    before do
      allow(tmdb).to receive(:tv).with("7").and_return(show)
      allow(tmdb).to receive(:season_episodes).with("7", "2").and_return(episodes)
      allow(tmdb).to receive(:episode_cast).with("7", "2", "3").and_return(cast)
    end

    it "lists seasons" do
      get cast_show_path(7)

      expect(response.body).to include(cast_season_path(7, 2), "3 episodes")
    end

    it "lists episodes" do
      get cast_season_path(7, 2)

      expect(response.body).to include(cast_episode_path(7, 2, 3), "The One")
    end

    it "shows an episode's cast with a lazy awards frame" do
      get cast_episode_path(7, 2, 3)

      expect(response.body).to include("Viola Davis", "The One")
      expect(response.body).to include(cast_table_path(kind: "episode", id: 7, season: 2, episode: 3).gsub("&", "&amp;"))
    end

    it "404s for an episode that does not exist" do
      get cast_episode_path(7, 2, 99)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /cast/table" do
    let(:egot) do
      EgotStatus.new(
        emmy: { won: true, wins: [ "Emmy Award winners" ] }, grammy: { won: true, wins: [ "Grammy Award winners" ] },
        oscar: { won: true, wins: [ "Academy Award winners" ] }, tony: { won: true, wins: [ "Tony Award winners" ] }
      )
    end
    let(:rows) do
      [
        CastEgotLookup::Row.new(member: cast[0], wikipedia_title: "Viola Davis", status: egot),
        CastEgotLookup::Row.new(member: cast[1], wikipedia_title: nil, status: nil)
      ]
    end

    before do
      allow(tmdb).to receive(:movie_cast).with("949").and_return(cast)
      allow_any_instance_of(CastEgotLookup).to receive(:call).with(cast).and_return(rows)
    end

    it "renders ticks for wins, a ? for unmatched people, and flags EGOTs" do
      get cast_table_path(kind: "movie", id: 949)

      body = response.body
      expect(body.scan("✓").size).to eq(4)
      expect(body.scan(">?<").size).to eq(4)
      expect(body).to include("🏆", "1 EGOT", "1 matched to Wikipedia", "https://en.wikipedia.org/wiki/Viola_Davis")
    end

    it "404s for an unknown kind" do
      get cast_table_path(kind: "nope", id: 1)

      expect(response).to have_http_status(:not_found)
    end
  end

  it "shows a friendly message when TMDb is down" do
    allow(tmdb).to receive(:search).and_raise(TmdbClient::Error)

    get cast_path(q: "heat")

    expect(response).to have_http_status(:bad_gateway)
    expect(response.body).to include("TMDb isn't responding")
  end
end
