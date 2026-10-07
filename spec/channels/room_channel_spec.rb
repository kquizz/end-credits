require "rails_helper"

RSpec.describe RoomChannel, type: :channel do
  let(:room_and_token) { Room.open!("Kevin") }
  let(:room) { room_and_token.first }
  let(:token) { room_and_token.last }

  it "streams a room to a seated player and sends them the current state with their seat" do
    stub_connection seats: { room.code => token }

    subscribe(code: room.code)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(room.stream_name)
    expect(transmissions.last).to include("code" => room.code, "you" => 0, "status" => "lobby")
  end

  it "lets a spectator subscribe read-only: no seat, the same public state" do
    stub_connection seats: {}

    subscribe(code: room.code)

    expect(subscription).to be_confirmed
    expect(transmissions.last["you"]).to be_nil
    expect(transmissions.last.keys).not_to include("players_tokens", "token")
  end

  it "does not honor a token that belongs to a different room or is wrong" do
    stub_connection seats: { room.code => "wrong", "OTHER1" => token }

    subscribe(code: room.code)

    expect(subscription).to be_confirmed
    expect(transmissions.last["you"]).to be_nil
  end

  it "never leaks seat tokens through the stream" do
    room.join!("Sam")
    stub_connection seats: {}

    subscribe(code: room.code)

    expect(transmissions.last.to_json).not_to include(token)
    expect(transmissions.last.to_json).not_to include(room.players.last["token"])
  end

  it "rejects an unknown room" do
    stub_connection seats: {}

    subscribe(code: "NOPE12")

    expect(subscription).to be_rejected
  end

  it "delivers broadcasts from moves to subscribers" do
    stub_connection seats: {}
    subscribe(code: room.code)

    expect { room.join!("Sam") }.to have_broadcasted_to(room.stream_name).with(hash_including(players: have_attributes(size: 2)))
  end
end

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "reads the seats from the signed cookie and treats junk as no seats" do
    connect "/cable", headers: { "HTTP_COOKIE" => "degrees_seats=garbage" }
    expect(connection.seats).to eq({})
  end
end
