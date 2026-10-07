require "rails_helper"

RSpec.describe "Costars", type: :request do
  let(:tmdb) { instance_double(TmdbClient) }

  before { allow(TmdbClient).to receive(:new).and_return(tmdb) }

  def member(id, name, episodes)
    TmdbClient::AggregateCastMember.new(person_id: id, name: name, total_episodes: episodes,
                                        roles: [ { character: "X", episode_count: episodes } ])
  end

  describe "GET /costars" do
    it "renders the picker without calling TMDb" do
      get costars_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Co-star Web", costars_overlap_path)
      expect(TmdbClient).not_to have_received(:new)
    end

    it "includes a hidden top-people toggle for the web view" do
      get costars_path

      toggle = Nokogiri::HTML(response.body).at_css("[data-costars-target=topBtn]")
      expect(toggle).to be_present
      expect(toggle["data-action"]).to eq("costars#toggleTop")
      expect(toggle.has_attribute?("hidden")).to be(true)
    end
  end

  describe "GET /costars with ids (shareable link)" do
    it "preloads the series titles for the picker and skips ones TMDb doesn't know" do
      allow(tmdb).to receive(:tv).with(81723).and_return({ name: "The Gilded Age", seasons: [] })
      allow(tmdb).to receive(:tv).with(1435).and_return({ name: "The Good Wife", seasons: [] })
      allow(tmdb).to receive(:tv).with(999).and_raise(TmdbClient::NotFound)

      get costars_path(ids: [ 81723, 1435, 999, "junk" ])

      expect(response).to have_http_status(:ok)
      preload = Nokogiri::HTML(response.body).at_css("[data-controller=costars]")["data-costars-preload-value"]
      expect(JSON.parse(preload)).to eq([ { "id" => 81723, "title" => "The Gilded Age" },
                                          { "id" => 1435, "title" => "The Good Wife" } ])
    end
  end

  describe "GET /costars/search" do
    it "returns only TV results" do
      allow(tmdb).to receive(:search).with("gild").and_return([
        TmdbClient::SearchResult.new(media_type: "movie", id: 1, title: "Gilda", year: 1946),
        TmdbClient::SearchResult.new(media_type: "tv", id: 81723, title: "The Gilded Age", year: 2022)
      ])

      get costars_search_path(q: "gild", format: :json)

      expect(response.parsed_body.map { |r| r["id"] }).to eq([ 81723 ])
    end
  end

  describe "GET /costars/search ordering" do
    def tv(id, title, popularity, poster: "https://img/#{id}.jpg", year: 2009)
      TmdbClient::SearchResult.new(media_type: "tv", id: id, title: title, year: year, poster_url: poster, popularity: popularity)
    end

    it "sorts by popularity and drops poster-less, barely popular junk" do
      allow(tmdb).to receive(:search).with("the good wife").and_return([
        tv(1, "The Good Wife (ru)", 3.0), tv(2, "The Trial", 0.4, poster: nil),
        tv(3, "The Good Wife", 60.0), tv(4, "Obscure but posterless", 9.0, poster: nil)
      ])

      get costars_search_path(q: "the good wife", format: :json)

      expect(response.parsed_body.map { |r| r["id"] }).to eq([ 3, 4, 1 ])
    end
  end

  describe "GET /costars/overlap" do
    it "returns the shared people" do
      allow(tmdb).to receive(:tv) { |id| { name: "Show #{id}", seasons: [] } }
      allow(tmdb).to receive(:tv_aggregate_credits).with(1).and_return([ member(10, "Ann", 4), member(11, "Bo", 1) ])
      allow(tmdb).to receive(:tv_aggregate_credits).with(2).and_return([ member(10, "Ann", 5) ])

      get costars_overlap_path(ids: [ 1, 2 ], format: :json)

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body["series"].map { |s| s["id"] }).to eq([ 1, 2 ])
      expect(body["people"].map { |p| [ p["name"], p["total_episodes"], p["size"] ] }).to eq([ [ "Ann", 9, 1.0 ] ])
    end

    it "asks for at least two series" do
      get costars_overlap_path(ids: [ 1 ], format: :json)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("at least 2")
    end

    it "gives a friendly message when TMDb doesn't know a series" do
      allow(tmdb).to receive(:tv).and_raise(TmdbClient::NotFound)

      get costars_overlap_path(ids: [ 1, 2 ], format: :json)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to be_present
    end

    it "gives a friendly message when TMDb fails" do
      allow(tmdb).to receive(:tv).and_raise(TmdbClient::Error)

      get costars_overlap_path(ids: [ 1, 2 ], format: :json)

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to include("TMDb")
    end
  end

  describe "GET /costars/watch_next" do
    def credit(id, title, character: "Role")
      TmdbClient::Credit.new(media_type: "tv", id: id, title: title, year: 2015, character: character,
                             genre_ids: [], episode_count: 3, poster_url: "p", popularity: 1.0)
    end

    it "returns titles shared by the given people, minus the selected series" do
      allow(tmdb).to receive(:people_credits).with([ 10, 11 ]).and_return(
        10 => [ credit(500, "Shared"), credit(1, "Picked"), credit(600, "Talk", character: "Self") ],
        11 => [ credit(500, "Shared"), credit(1, "Picked"), credit(600, "Talk", character: "Self") ]
      )

      get costars_watch_next_path(ids: [ 10, 11 ], series: [ 1 ], format: :json)

      body = response.parsed_body
      expect(response).to have_http_status(:ok)
      expect(body["titles"].map { |t| [ t["title"], t["member_count"], t["person_ids"] ] }).to eq([ [ "Shared", 2, [ 10, 11 ] ] ])
      expect(body).to include("people_checked" => 2, "people_skipped" => 0)
    end

    it "honors the filter toggles" do
      allow(tmdb).to receive(:people_credits).and_return(
        10 => [ credit(600, "Talk", character: "Self") ], 11 => [ credit(600, "Talk", character: "Self") ]
      )

      get costars_watch_next_path(ids: [ 10, 11 ], skip_self: "0", format: :json)

      expect(response.parsed_body["titles"].map { |t| t["title"] }).to eq([ "Talk" ])
    end

    it "asks for at least two people" do
      get costars_watch_next_path(ids: [ 10 ], format: :json)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("at least 2")
    end

    it "gives a friendly message when TMDb fails" do
      allow(tmdb).to receive(:people_credits).and_raise(TmdbClient::Error)

      get costars_watch_next_path(ids: [ 10, 11 ], format: :json)

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to include("TMDb")
    end
  end

  it "renders the watch-next hooks on the page" do
    get costars_path

    expect(response.body).to include(costars_watch_next_path)
  end
end
