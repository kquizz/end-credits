require "rails_helper"

RSpec.describe "Degrees", type: :request do
  let(:tmdb) { instance_double(TmdbClient) }
  let(:check) { instance_double(ConnectionCheck) }
  let(:shared) { [ { id: 10, title: "Heat", year: 1995, media_type: "movie", poster_url: "p" } ] }

  before do
    allow(TmdbClient).to receive(:new).and_return(tmdb)
    allow(ConnectionCheck).to receive(:new).and_return(check)
  end

  def person(id, name) = TmdbClient::PersonResult.new(id: id, name: name, known_for: [], photo_url: "#{name}.jpg")

  describe "GET /degrees/people" do
    it "returns suggestions with photo and known-for titles" do
      allow(tmdb).to receive(:search_person).with("al pa").and_return([
        TmdbClient::PersonResult.new(id: 1158, name: "Al Pacino", known_for: [ "Heat" ], photo_url: "a.jpg")
      ])

      get degrees_people_path(q: "al pa")

      expect(response.parsed_body).to eq([ { "id" => 1158, "name" => "Al Pacino", "photo_url" => "a.jpg", "known_for" => [ "Heat" ] } ])
    end

    it "caps the list" do
      allow(tmdb).to receive(:search_person).and_return(Array.new(20) { |i| person(i + 1, "P#{i}") })

      get degrees_people_path(q: "p")

      expect(response.parsed_body.size).to eq(DegreesController::MAX_SUGGESTIONS)
    end

    it "answers 502 with a friendly message when TMDb is down" do
      allow(tmdb).to receive(:search_person).and_raise(TmdbClient::Error)

      get degrees_people_path(q: "x")

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["message"]).to match(/TMDb isn't responding/)
    end
  end

  describe "GET /degrees/guess" do
    before do
      allow(tmdb).to receive(:person).with(1).and_return(person(1, "Robert De Niro"))
      allow(tmdb).to receive(:person).with(2).and_return(person(2, "Al Pacino"))
    end

    it "accepts a guess that shares a credit and returns the titles and the person" do
      allow(check).to receive(:call).with(1, 2, anything).and_return(shared)

      get degrees_guess_path(chain_last_id: 1, guess_id: 2, chain: [ 9, 1 ])

      expect(response.parsed_body).to include("ok" => true, "titles" => [ hash_including("title" => "Heat") ],
                                              "person" => { "id" => 2, "name" => "Al Pacino", "photo_url" => "Al Pacino.jpg" })
    end

    it "passes the rule flags, defaulting to no Self and no voice" do
      allow(check).to receive(:call).and_return(shared)

      get degrees_guess_path(chain_last_id: 1, guess_id: 2, skip_marvel: "true", movies_only: "1", year_from: 2000, year_to: 1990)

      expect(check).to have_received(:call).with(
        1, 2, skip_self: true, skip_voice: true, skip_marvel: true, movies_only: true, years: 1990..2000
      )
    end

    it "lets the rules be switched off" do
      allow(check).to receive(:call).and_return(shared)

      get degrees_guess_path(chain_last_id: 1, guess_id: 2, skip_self: "false", skip_voice: "false")

      expect(check).to have_received(:call).with(
        1, 2, skip_self: false, skip_voice: false, skip_marvel: false, movies_only: false, years: nil
      )
    end

    it "says no (200, ok false) when nothing is shared" do
      allow(check).to receive(:call).and_return([])

      get degrees_guess_path(chain_last_id: 1, guess_id: 2)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => false)
      expect(response.parsed_body["message"]).to include("Al Pacino", "Robert De Niro")
    end

    it "rejects someone already in the chain without checking credits" do
      allow(check).to receive(:call)
      get degrees_guess_path(chain_last_id: 1, guess_id: 2, chain: [ 2, 1 ])

      expect(response.parsed_body).to include("ok" => false)
      expect(response.parsed_body["message"]).to include("already in your chain")
      expect(check).not_to have_received(:call)
    end

    it "rejects a missing guess with 422" do
      get degrees_guess_path(chain_last_id: 1)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["ok"]).to be(false)
    end

    it "answers 404 for a person TMDb doesn't know" do
      allow(tmdb).to receive(:person).with(3).and_raise(TmdbClient::NotFound)

      get degrees_guess_path(chain_last_id: 1, guess_id: 3)

      expect(response).to have_http_status(:not_found)
    end

    it "answers 502 when the credits lookup fails" do
      allow(check).to receive(:call).and_raise(TmdbClient::Error)

      get degrees_guess_path(chain_last_id: 1, guess_id: 2)

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["ok"]).to be(false)
    end
  end
end
