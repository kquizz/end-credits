require "rails_helper"

RSpec.describe "Ages", type: :request do
  let(:tmdb) { instance_double(TmdbClient) }
  let(:cast) do
    [
      TmdbClient::CastMember.new(person_id: 1, name: "Young Star", character: "Lead"),
      TmdbClient::CastMember.new(person_id: 2, name: "Old Hand", character: "Mentor"),
      TmdbClient::CastMember.new(person_id: 3, name: "Late Legend", character: "Ghost"),
      TmdbClient::CastMember.new(person_id: 4, name: "Mystery Guest", character: "Cameo")
    ]
  end
  let(:release) { Date.new(1995, 12, 15) }

  before { allow(TmdbClient).to receive(:new).and_return(tmdb) }

  it "searches and links into the ages routes, not the EGOT ones" do
    allow(tmdb).to receive(:search).and_return([ TmdbClient::SearchResult.new(media_type: "movie", id: 949, title: "Heat", year: 1995) ])

    get ages_path(q: "heat")

    expect(response.body).to include(ages_movie_path(949), "Cast Ages")
    expect(response.body).not_to include(cast_movie_path(949))
  end

  it "shows the release date and a lazy frame pointing at the ages table" do
    allow(tmdb).to receive(:movie).with("949").and_return(TmdbClient::Title.new(id: 949, name: "Heat", date: release))
    allow(tmdb).to receive(:movie_cast).with("949").and_return(cast)

    get ages_movie_path(949)

    expect(response.body).to include("Released December 15, 1995", "Young Star")
    expect(response.body).to include(ages_table_path(kind: "movie", id: 949).gsub("&", "&amp;"))
  end

  it "shows an episode's air date" do
    allow(tmdb).to receive(:tv).and_return({ name: "Show", seasons: [] })
    allow(tmdb).to receive(:season_episodes).with("7", "2")
      .and_return([ TmdbClient::Episode.new(number: 3, name: "The One", date: Date.new(2020, 1, 2)) ])
    allow(tmdb).to receive(:episode_cast).with("7", "2", "3").and_return(cast)

    get ages_episode_path(7, 2, 3)

    expect(response.body).to include("Aired January 2, 2020")
  end

  describe "GET /ages/table" do
    before do
      allow(tmdb).to receive(:movie).with("949").and_return(TmdbClient::Title.new(id: 949, name: "Heat", date: release))
      allow(tmdb).to receive(:movie_cast).with("949").and_return(cast)
      allow(tmdb).to receive(:people_details).and_return(
        1 => TmdbClient::PersonDetails.new(birthday: Date.new(1975, 1, 1)),
        2 => TmdbClient::PersonDetails.new(birthday: Date.new(1930, 3, 3), deathday: Date.new(2015, 1, 1)),
        3 => TmdbClient::PersonDetails.new(birthday: Date.new(1920, 1, 1), deathday: Date.new(1990, 1, 1)),
        4 => TmdbClient::PersonDetails.new(birthday: nil)
      )
    end

    it "renders ages, death markers, a dagger, a ?, and summary stats" do
      get ages_table_path(kind: "movie", id: 949)

      body = response.body
      expect(body).to include(">20<", ">65<")              # 1975 -> 20, 1930 -> 65 on 1995-12-15
      expect(body).to include("(d. 2015)", "†")
      expect(body).to include(">?<")
      expect(body).to include("oldest Old Hand (65)", "youngest Young Star (20)", "average 43")
    end

    it "explains itself when there is no premiere date" do
      allow(tmdb).to receive(:movie).with("949").and_return(TmdbClient::Title.new(id: 949, name: "Heat", date: nil))

      get ages_table_path(kind: "movie", id: 949)

      expect(response.body).to include("no premiere date")
    end
  end
end
