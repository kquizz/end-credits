require "rails_helper"

RSpec.describe RoomGame do
  let(:start) { { id: 1, name: "Start", photo_url: "s.jpg" } }
  let(:target) { { id: 9, name: "Target", photo_url: "t.jpg" } }
  let(:titles) { [ { id: 10, title: "Heat", year: 1995, media_type: "movie" } ] }
  let(:lobby) { described_class.join(described_class.initial) }

  def begin_round(state, seat: 0)
    described_class.start_round(state, seat, expected_round: state[:round_number], start: start, target: target)
  end

  def person(id) = { id: id, name: "P#{id}", photo_url: nil }

  def link(state, seat, id)
    described_class.guess(state, seat, person: person(id), titles: titles, expected_last_id: state[:chain].last[:id])
  end

  def illegal(message = nil, &) = raise_error(described_class::IllegalMove, message ? /#{message}/ : nil, &)

  describe "joining and rules" do
    it "starts with one player, and a second can join but not a third" do
      expect(described_class.initial[:players]).to eq(1)
      expect(lobby[:players]).to eq(2)
      expect { described_class.join(lobby) }.to illegal("full")
    end

    it "lets only the creator change rules, only between rounds, ignoring unknown keys" do
      state = described_class.set_rules(lobby, 0, { skip_marvel: "true", movies_only: true, bogus: true })
      expect(state[:rules]).to eq(skip_self: true, skip_voice: true, skip_marvel: true, movies_only: true)
      expect { described_class.set_rules(lobby, 1, { skip_self: false }) }.to illegal("creator")
      expect { described_class.set_rules(begin_round(lobby), 0, { skip_self: false }) }.to illegal("locked")
      over = described_class.give_up(described_class.call(described_class.bid(begin_round(lobby), 0, 3), 1), 0)
      expect(described_class.set_rules(over, 0, { skip_self: false })[:rules][:skip_self]).to be(false)
    end
  end

  describe "starting a round" do
    it "needs two players" do
      expect { begin_round(described_class.initial) }.to illegal("second player")
    end

    it "deals the pair, a one-person chain, and lets the creator open round 1" do
      state = begin_round(lobby)
      expect(state).to include(status: "bidding", round_number: 1, opener: 0, turn: 0, bids: [])
      expect(state[:chain]).to eq([ start.merge(via: nil) ])
      expect(state[:target]).to eq(target)
    end

    it "is idempotent: a stale 'Next round' click changes nothing" do
      state = begin_round(lobby)
      stale = described_class.start_round(state, 1, expected_round: 0, start: person(5), target: person(6))
      expect(stale).to eq(state)
      expect(described_class.startable?(state, 0)).to be(false)
    end

    it "refuses to restart a round in play" do
      state = begin_round(lobby)
      expect { described_class.start_round(state, 0, expected_round: 1, start: start, target: target) }.to illegal("still in play")
    end

    it "alternates who opens each round" do
      state = lobby
      openers = 3.times.map do
        state = begin_round(state)
        state[:opener].tap { state = described_class.give_up(described_class.call(described_class.bid(state, state[:opener], 2), 1 - state[:opener]), state[:opener]) }
      end
      expect(openers).to eq([ 0, 1, 0 ])
    end

    it "keeps the scores across rounds" do
      state = described_class.give_up(described_class.call(described_class.bid(begin_round(lobby), 0, 3), 1), 0)
      expect(state[:scores]).to eq([ 0, 1 ])
      expect(begin_round(state)[:scores]).to eq([ 0, 1 ])
    end

    it "rejects spectators" do
      expect { begin_round(lobby, seat: 2) }.to illegal("watching")
    end
  end

  describe "bidding" do
    let(:state) { begin_round(lobby) }

    it "passes the turn after each bid" do
      after = described_class.bid(state, 0, 5)
      expect(after).to include(turn: 1, bids: [ { seat: 0, hops: 5 } ])
    end

    it "accepts bids as strings and rejects junk and out-of-range values" do
      expect(described_class.bid(state, 0, "4")[:bids].last[:hops]).to eq(4)
      expect { described_class.bid(state, 0, "four") }.to illegal("whole number")
      expect { described_class.bid(state, 0, 0) }.to illegal("1 to 6")
      expect { described_class.bid(state, 0, 7) }.to illegal("1 to 6")
    end

    it "demands each bid be strictly lower than the last" do
      after = described_class.bid(state, 0, 4)
      expect { described_class.bid(after, 1, 4) }.to illegal("lower than 4")
      expect { described_class.bid(after, 1, 5) }.to illegal("lower than 4")
      expect(described_class.bid(after, 1, 3)[:turn]).to eq(0)
    end

    it "rejects out-of-turn bids" do
      expect { described_class.bid(state, 1, 5) }.to illegal("not your turn")
    end

    it "rejects bids outside the bidding phase" do
      expect { described_class.bid(lobby, 0, 3) }.to illegal("nothing to bid")
    end

    it "can't be called before anyone has bid" do
      expect { described_class.call(state, 0) }.to illegal("Nobody has bid")
    end

    it "can't be called out of turn" do
      expect { described_class.call(described_class.bid(state, 0, 4), 0) }.to illegal("not your turn")
    end
  end

  describe "the challenge" do
    let(:called) { described_class.call(described_class.bid(described_class.bid(begin_round(lobby), 0, 4), 1, 3), 0) }

    it "makes the lowest bidder the challenger" do
      expect(called).to include(status: "challenge", challenger: 1, turn: 1)
      expect(described_class.hops_remaining(called)).to eq(3)
    end

    it "no longer accepts bids" do
      expect { described_class.bid(called, 1, 2) }.to illegal("nothing to bid")
    end

    it "extends the chain and counts hops down" do
      state = link(called, 1, 2)
      expect(state[:chain].map { |n| n[:id] }).to eq([ 1, 2 ])
      expect(state[:chain].last[:via]).to eq(titles)
      expect(described_class.hops_remaining(state)).to eq(2)
      expect(state[:status]).to eq("challenge")
    end

    it "wins the round for the challenger when the target is reached within the bid" do
      state = link(link(called, 1, 2), 1, 9)
      expect(state).to include(status: "round_over", scores: [ 0, 1 ])
      expect(state[:result]).to include(winner: 1, kind: "connected", hops: 2, bid: 3)
    end

    it "wins when the target arrives on exactly the last allowed hop" do
      state = link(link(link(called, 1, 2), 1, 3), 1, 9)
      expect(state[:result]).to include(winner: 1, kind: "connected", hops: 3)
    end

    it "gives the round to the opponent when the hops run out short of the target" do
      state = link(link(link(called, 1, 2), 1, 3), 1, 4)
      expect(state).to include(status: "round_over", scores: [ 1, 0 ])
      expect(state[:result]).to include(winner: 0, kind: "out_of_hops", hops: 3)
    end

    it "gives the round to the opponent when the challenger gives up" do
      state = described_class.give_up(link(called, 1, 2), 1)
      expect(state[:result]).to include(winner: 0, kind: "gave_up")
      expect(state[:scores]).to eq([ 1, 0 ])
    end

    it "keeps the opponent out of it" do
      expect { link(called, 0, 2) }.to illegal("challenger")
      expect { described_class.give_up(called, 0) }.to illegal("challenger")
    end

    it "rejects repeats, stale chain ends and unverified guesses" do
      expect { link(called, 1, 1) }.to illegal("already in the chain")
      expect { described_class.guess(called, 1, person: person(2), titles: titles, expected_last_id: 77) }.to illegal("chain moved")
      expect { described_class.guess(called, 1, person: person(2), titles: [], expected_last_id: 1) }.to illegal("doesn't connect")
    end

    it "rejects guesses once the round is over" do
      over = described_class.give_up(called, 1)
      expect { link(over, 1, 2) }.to illegal("Nobody is building")
    end

    it "does not mutate the state it was given" do
      before = Marshal.load(Marshal.dump(called))
      link(called, 1, 2)
      expect(called).to eq(before)
    end
  end

  it "wins a one-hop bid only by connecting directly" do
    called = described_class.call(described_class.bid(begin_round(lobby), 0, 1), 1)
    expect(link(called, 0, 9)[:result]).to include(winner: 0, kind: "connected", hops: 1)
    expect(link(called, 0, 2)[:result]).to include(winner: 1, kind: "out_of_hops")
  end
end
