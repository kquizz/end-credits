require "rails_helper"

RSpec.describe Room do
  let(:start) { { id: 1, name: "Start", photo_url: nil } }
  let(:target) { { id: 9, name: "Target", photo_url: nil } }

  def started_room
    room, tokens = described_class.open!("Kevin").then { |r, t| [ r, [ t ] ] }
    tokens << room.join!("Sam")
    room.transition! { |g| RoomGame.start_round(g, 0, expected_round: 0, start: start, target: target) }
    [ room, tokens ]
  end

  describe ".open!" do
    it "creates a room with a short unambiguous code and the creator in seat 0" do
      room, token = described_class.open!("  Kevin  ")

      expect(room.code).to match(/\A[2-9A-HJKMNP-Z]{6}\z/)
      expect(room.players.first).to include("name" => "Kevin")
      expect(room.seat_for(token)).to eq(0)
      expect(room.game).to include(status: "lobby", players: 1)
    end

    it "defaults and trims names" do
      room, = described_class.open!("")
      expect(room.players.first["name"]).to eq("Player 1")
      expect(described_class.clean_name("x" * 60, 2).size).to eq(Room::MAX_NAME)
    end

    it "retries when a code collides" do
      allow(described_class).to receive(:random_code).and_return("ABCDEF", "ABCDEF", "ZZZZZZ")
      described_class.open!("a")

      room, = described_class.open!("b")

      expect(room.code).to eq("ZZZZZZ")
    end
  end

  describe "seats" do
    it "finds a seat by token only" do
      room, token = described_class.open!("A")
      expect(room.seat_for(token)).to eq(0)
      expect(room.seat_for("nope")).to be_nil
      expect(room.seat_for(nil)).to be_nil
    end

    it "seats a second player, then refuses a third" do
      room, = described_class.open!("A")
      token = room.join!("")

      expect(room.reload.seat_for(token)).to eq(1)
      expect(room.players.last["name"]).to eq("Player 2")
      expect(room).to be_full
      expect { room.join!("C") }.to raise_error(RoomGame::IllegalMove)
      expect(room.reload.players.size).to eq(2)
    end

    it "renames a player and bumps the version" do
      room, = described_class.open!("A")
      expect { room.rename!(0, "Zed") }.to change { room.reload.game[:version] }.by(1)
      expect(room.players.first["name"]).to eq("Zed")
    end
  end

  describe "#transition!" do
    it "persists the new state and broadcasts the sanitized state" do
      room, = described_class.open!("A")
      room.join!("B")

      expect {
        room.transition! { |g| RoomGame.start_round(g, 0, expected_round: 0, start: start, target: target) }
      }.to have_broadcasted_to(room.stream_name).with(hash_including(status: "bidding", round_number: 1))
      expect(room.reload.game[:status]).to eq("bidding")
    end

    it "rolls back and does not broadcast an illegal move" do
      room, = started_room
      before = room.reload.state

      expect {
        expect { room.transition! { |g| RoomGame.bid(g, 1, 3) } }.to raise_error(RoomGame::IllegalMove)
      }.not_to have_broadcasted_to(room.stream_name)
      expect(room.reload.state).to eq(before)
    end
  end

  describe "#public_state" do
    it "never includes tokens" do
      room, tokens = started_room
      json = room.public_state.to_json

      tokens.each { |t| expect(json).not_to include(t) }
      expect(json).not_to include("token")
      expect(room.public_state).to include(code: room.code, max_hops: nil, hops_remaining: nil,
                                           players: [ { seat: 0, name: "Kevin" }, { seat: 1, name: "Sam" } ])
    end

    it "exposes the bid and hops remaining during a challenge" do
      room, = started_room
      room.transition! { |g| RoomGame.call(RoomGame.bid(g, 0, 3), 1) }
      expect(room.public_state).to include(max_hops: 3, hops_remaining: 3, challenger: 0)
    end
  end

  describe ".purge_idle!" do
    it "deletes rooms idle for more than a day and keeps fresh ones" do
      old, = described_class.open!("old")
      fresh, = described_class.open!("fresh")
      old.update_columns(updated_at: 25.hours.ago)

      described_class.purge_idle!

      expect(described_class.pluck(:id)).to eq([ fresh.id ])
    end
  end
end
