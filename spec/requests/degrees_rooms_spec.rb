require "rails_helper"

RSpec.describe "Degrees rooms", type: :request do
  let(:tmdb) { instance_double(TmdbClient) }
  let(:check) { instance_double(ConnectionCheck) }
  let(:start) { { id: 1, name: "Start", photo_url: "s.jpg" } }
  let(:target) { { id: 9, name: "Target", photo_url: "t.jpg" } }
  let(:generator) { instance_double(PairGenerator, call: PairGenerator::Pair.new(start: start, target: target, hops: 3, walk: [], fallback: false)) }
  let(:shared) { [ { id: 10, title: "Heat", year: 1995, media_type: "movie", poster_url: "p" } ] }
  let(:kevin) { open_session }
  let(:sam) { open_session }
  let(:code) { Room.last.code }

  before do
    allow(TmdbClient).to receive(:new).and_return(tmdb)
    allow(ConnectionCheck).to receive(:new).and_return(check)
    allow(PairGenerator).to receive(:new).and_return(generator)
    allow(tmdb).to receive(:person) { |id| TmdbClient::PersonResult.new(id: id, name: "Person #{id}", known_for: [], photo_url: "#{id}.jpg") }
  end

  def room_path(suffix = nil) = "/degrees/rooms/#{code}#{suffix}"
  def json(session) = JSON.parse(session.response.body)
  def state(session) = json(session)["state"]

  def create_room(session = kevin, name: "Kevin")
    session.post "/degrees/rooms", params: { name: name }
  end

  def seat_both
    create_room
    sam.post room_path("/join"), params: { name: "Sam" }
  end

  def start_round(round = 0)
    kevin.post room_path("/next_round"), params: { round_number: round }
  end

  describe "POST /degrees/rooms" do
    it "creates a room, seats the creator via a signed cookie and redirects to the room" do
      create_room(name: "Kevin")

      expect(kevin.response).to have_http_status(:found)
      expect(kevin.response.location).to end_with("/degrees/rooms/#{code}")
      expect(Room.count).to eq(1)
      expect(Room.last.players.first["name"]).to eq("Kevin")
      expect(kevin.cookies["degrees_seats"]).to be_present
      expect(kevin.cookies["degrees_seats"]).not_to include(Room.last.players.first["token"])
    end
  end

  describe "GET /degrees/rooms/:code" do
    it "shows the creator the invite link while waiting" do
      create_room
      kevin.get room_path

      expect(kevin.response).to have_http_status(:ok)
      page = Nokogiri::HTML(kevin.response.body)
      game = page.at_css("[data-controller=room]")
      expect(game["data-room-code-value"]).to eq(code)
      expect(game["data-room-you-value"]).to eq("0")
      expect(game["data-room-invite-url-value"]).to end_with("/degrees/rooms/#{code}")
      expect(page.at_css("form[action$='/join']")).to be_nil
    end

    it "offers a stranger a join form while a seat is open, without seating them" do
      create_room
      sam.get room_path

      expect(Nokogiri::HTML(sam.response.body).at_css("form[action='#{room_path('/join')}']")).to be_present
      expect(Room.last.players.size).to eq(1)
    end

    it "lets a third visitor watch a full room read-only" do
      seat_both
      stranger = open_session
      stranger.get room_path

      page = Nokogiri::HTML(stranger.response.body)
      expect(page.at_css("form[action$='/join']")).to be_nil
      expect(page.at_css("[data-controller=room]")["data-room-you-value"]).to eq("")
      expect(stranger.response.body).to include("Room full")
    end

    it "keeps your seat across reloads" do
      seat_both
      sam.get room_path

      expect(Nokogiri::HTML(sam.response.body).at_css("[data-controller=room]")["data-room-you-value"]).to eq("1")
    end

    it "is a 404 for a missing room" do
      get "/degrees/rooms/NOPE12"
      expect(response).to have_http_status(:not_found)
    end

    it "serves the sanitized state as JSON, with no seat tokens, to players and spectators" do
      seat_both
      tokens = Room.last.players.map { |p| p["token"] }
      stranger = open_session

      [ kevin, sam, stranger ].each do |session|
        session.get room_path, headers: { "Accept" => "application/json" }
        expect(session.response.body).not_to include(*tokens)
        expect(json(session)["state"]).to include("code" => code, "status" => "lobby",
                                                  "players" => [ { "seat" => 0, "name" => "Kevin" }, { "seat" => 1, "name" => "Sam" } ])
      end
      expect(json(kevin)["you"]).to eq(0)
      expect(json(stranger)["you"]).to be_nil
    end

    it "ignores a forged or foreign seat cookie" do
      seat_both
      other = open_session
      other.cookies["degrees_seats"] = "garbage"
      other.get room_path, headers: { "Accept" => "application/json" }

      expect(json(other)["you"]).to be_nil
    end
  end

  describe "joining" do
    it "seats the second player, who then keeps the seat" do
      create_room
      sam.post room_path("/join"), params: { name: "Sam" }

      expect(sam.response).to have_http_status(:found)
      expect(sam.response.location).to end_with(room_path)
      expect(Room.last.players.map { |p| p["name"] }).to eq(%w[Kevin Sam])
      sam.get room_path, headers: { "Accept" => "application/json" }
      expect(json(sam)["you"]).to eq(1)
    end

    it "does not seat a third person or let them play" do
      seat_both
      stranger = open_session
      stranger.post room_path("/join"), params: { name: "Eve" }

      expect(Room.last.players.size).to eq(2)
      stranger.post room_path("/bid"), params: { hops: 3 }, headers: { "Accept" => "application/json" }
      expect(stranger.response).to have_http_status(:forbidden)
    end

    it "is harmless to join twice" do
      seat_both
      sam.post room_path("/join"), params: { name: "Sam again" }

      expect(Room.last.players.map { |p| p["name"] }).to eq(%w[Kevin Sam])
    end

    it "broadcasts the new player to the room" do
      create_room
      expect { sam.post room_path("/join"), params: { name: "Sam" } }
        .to have_broadcasted_to(Room.last.stream_name).with(hash_including(players: [ { seat: 0, name: "Kevin" }, { seat: 1, name: "Sam" } ]))
    end
  end

  describe "naming and rules" do
    before { seat_both }

    it "renames a player" do
      sam.post room_path("/set_name"), params: { name: "  Samwise " }
      expect(state(sam)["players"].last["name"]).to eq("Samwise")
    end

    it "lets only the creator change rules" do
      kevin.post room_path("/set_rules"), params: { rules: { skip_marvel: "true", movies_only: "true" } }
      expect(state(kevin)["rules"]).to include("skip_marvel" => true, "movies_only" => true, "skip_self" => true)

      sam.post room_path("/set_rules"), params: { rules: { skip_self: "false" } }
      expect(sam.response).to have_http_status(:unprocessable_content)
      expect(json(sam)["message"]).to match(/creator/)
    end

    it "locks the rules once a round is in play" do
      start_round
      kevin.post room_path("/set_rules"), params: { rules: { skip_self: "false" } }
      expect(kevin.response).to have_http_status(:unprocessable_content)
    end
  end

  describe "playing a round" do
    before do
      seat_both
      start_round
    end

    it "deals both players the same pair, with the creator opening round 1" do
      expect(state(kevin)).to include("status" => "bidding", "round_number" => 1, "turn" => 0)
      expect(state(kevin)["start"]).to include("id" => 1, "name" => "Start")
      expect(state(kevin)["target"]).to include("id" => 9)
      expect(state(kevin).to_json).not_to include("walk")
      expect(PairGenerator).to have_received(:new).with(hash_including(rules: hash_including(skip_self: true)))
    end

    it "makes next_round idempotent: the second click does not draw another pair" do
      sam.post room_path("/next_round"), params: { round_number: 0 }

      expect(sam.response).to have_http_status(:ok)
      expect(state(sam)["round_number"]).to eq(1)
      expect(generator).to have_received(:call).once
    end

    it "rejects out-of-turn and illegal bids with a clear message and the current state" do
      sam.post room_path("/bid"), params: { hops: 3 }
      expect(sam.response).to have_http_status(:unprocessable_content)
      expect(json(sam)).to include("ok" => false, "message" => "It's not your turn.")
      expect(json(sam)["state"]["status"]).to eq("bidding")

      kevin.post room_path("/bid"), params: { hops: 4 }
      sam.post room_path("/bid"), params: { hops: 4 }
      expect(json(sam)["message"]).to match(/lower than 4/)
    end

    it "broadcasts every move to the room" do
      expect { kevin.post room_path("/bid"), params: { hops: 4 } }
        .to have_broadcasted_to(Room.last.stream_name).with(hash_including(turn: 1, bids: [ { seat: 0, hops: 4 } ]))
    end

    it "runs the whole challenge: bid, go for it, wrong guess, hops, win, scoreboard, next round" do
      kevin.post room_path("/bid"), params: { hops: 3 }
      sam.post room_path("/bid"), params: { hops: 2 }
      kevin.post room_path("/challenge")
      expect(state(kevin)).to include("status" => "challenge", "challenger" => 1, "max_hops" => 2, "hops_remaining" => 2)

      # The opponent can't build the chain, and a spectator can't either.
      kevin.post room_path("/guess"), params: { guess_id: 5 }
      expect(kevin.response).to have_http_status(:unprocessable_content)

      allow(check).to receive(:call).with(1, 5, anything).and_return([])
      sam.post room_path("/guess"), params: { guess_id: 5 }
      expect(sam.response).to have_http_status(:ok)
      expect(json(sam)).to include("ok" => false)
      expect(json(sam)["message"]).to match(/hasn't shared a credit with Start/)
      expect(state(sam)["chain"].size).to eq(1) # no hop spent

      allow(check).to receive(:call).with(1, 5, anything).and_return(shared)
      allow(check).to receive(:call).with(5, 9, anything).and_return(shared)
      sam.post room_path("/guess"), params: { guess_id: 5 }
      expect(state(sam)["chain"].map { |n| n["id"] }).to eq([ 1, 5 ])
      expect(state(sam)["hops_remaining"]).to eq(1)

      sam.post room_path("/guess"), params: { guess_id: 5 }
      expect(json(sam)["message"]).to match(/already in the chain/)

      sam.post room_path("/guess"), params: { guess_id: 9 }
      expect(state(sam)).to include("status" => "round_over", "scores" => [ 0, 1 ])
      expect(state(sam)["result"]).to include("winner" => 1, "kind" => "connected", "hops" => 2, "bid" => 2)

      kevin.post room_path("/next_round"), params: { round_number: 1 }
      expect(state(kevin)).to include("status" => "bidding", "round_number" => 2, "opener" => 1, "turn" => 1, "scores" => [ 0, 1 ])
    end

    it "gives the round to the opponent when the challenger gives up" do
      kevin.post room_path("/bid"), params: { hops: 2 }
      sam.post room_path("/challenge")
      kevin.post room_path("/give_up")

      expect(state(kevin)).to include("status" => "round_over", "scores" => [ 0, 1 ])
      expect(state(kevin)["result"]["kind"]).to eq("gave_up")
    end

    it "gives the round to the opponent when the challenger runs out of hops" do
      kevin.post room_path("/bid"), params: { hops: 1 }
      sam.post room_path("/challenge")
      allow(check).to receive(:call).and_return(shared)
      kevin.post room_path("/guess"), params: { guess_id: 5 }

      expect(state(kevin)["result"]).to include("winner" => 1, "kind" => "out_of_hops")
    end

    it "validates guesses on the server and never trusts the client" do
      kevin.post room_path("/bid"), params: { hops: 2 }
      sam.post room_path("/challenge")
      allow(check).to receive(:call).and_return([])
      kevin.post room_path("/guess"), params: { guess_id: 9 }

      expect(state(kevin)["status"]).to eq("challenge")
      expect(kevin.response.body).not_to include('"result":{')
    end

    it "asks for a guess id" do
      kevin.post room_path("/bid"), params: { hops: 2 }
      sam.post room_path("/challenge")
      kevin.post room_path("/guess")
      expect(kevin.response).to have_http_status(:unprocessable_content)
    end

    it "answers 502 when TMDb is down" do
      kevin.post room_path("/bid"), params: { hops: 2 }
      sam.post room_path("/challenge")
      allow(tmdb).to receive(:person).and_raise(TmdbClient::Error)
      kevin.post room_path("/guess"), params: { guess_id: 4 }

      expect(kevin.response).to have_http_status(:bad_gateway)
    end
  end
end
