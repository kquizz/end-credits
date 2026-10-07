# The Six Degrees bidding game as a pure state machine (no I/O, no clock). Every move takes the current
# state hash (symbol keys) and returns a NEW state, or raises IllegalMove with a message for the player.
# The Room model persists the state under a row lock, so two clicks at once can't both apply.
#
# Seats are 0 and 1 (the room creator is 0). Statuses:
#   lobby      waiting for players / the first round
#   bidding    players alternate "I can do it in N hops", each bid strictly lower than the last
#   challenge  the lowest bidder builds start -> target within their bid; the other player watches
#   round_over someone won; either player can start the next round
module RoomGame
  class IllegalMove < StandardError; end

  MAX_BID = 6
  RULE_DEFAULTS = { skip_self: true, skip_voice: true, skip_marvel: false, movies_only: false }.freeze
  SEATS = [ 0, 1 ].freeze

  module_function

  def initial
    { status: "lobby", players: 1, round_number: 0, opener: nil, turn: nil, bids: [], challenger: nil,
      chain: [], start: nil, target: nil, scores: [ 0, 0 ], result: nil, rules: RULE_DEFAULTS.dup, version: 0 }
  end

  def join(state)
    raise IllegalMove, "This room is full." if state[:players] >= 2

    bump(state, players: 2)
  end

  # The creator tunes the shared rules between rounds; they're locked while a round is in play.
  def set_rules(state, seat, rules)
    require_seat!(state, seat)
    raise IllegalMove, "Only the room creator can change the rules." unless seat == 0
    raise IllegalMove, "Rules are locked while a round is in play." unless %w[lobby round_over].include?(state[:status])

    given = rules.to_h.symbolize_keys
    cleaned = RULE_DEFAULTS.keys.to_h { |k| [ k, given.key?(k) ? truthy?(given[k]) : state[:rules][k] ] }
    bump(state, rules: cleaned)
  end

  def startable?(state, expected_round)
    state[:round_number] == expected_round && %w[lobby round_over].include?(state[:status]) && state[:players] == 2
  end

  # Draws a fresh round. Idempotent: a stale click (the round already moved on) changes nothing, so the
  # first of two simultaneous "Next round" clicks wins and the second is a no-op.
  def start_round(state, seat, expected_round:, start:, target:)
    require_seat!(state, seat)
    return state if state[:round_number] != expected_round
    raise IllegalMove, "Waiting for a second player." if state[:players] < 2
    raise IllegalMove, "The round is still in play." unless %w[lobby round_over].include?(state[:status])

    opener = state[:opener].nil? ? 0 : 1 - state[:opener]
    bump(state, status: "bidding", round_number: state[:round_number] + 1, opener: opener, turn: opener, bids: [],
                challenger: nil, chain: [ slim(start).merge(via: nil) ], start: slim(start), target: slim(target),
                result: nil)
  end

  def bid(state, seat, hops)
    require_status!(state, "bidding", "There's nothing to bid on right now.")
    require_turn!(state, seat)
    hops = Integer(hops, exception: false)
    raise IllegalMove, "Bid a whole number of hops." unless hops
    raise IllegalMove, "Bids run from 1 to #{MAX_BID} hops." unless (1..MAX_BID).cover?(hops)

    lowest = state[:bids].last&.fetch(:hops)
    raise IllegalMove, "Your bid has to be lower than #{lowest}." if lowest && hops >= lowest

    bump(state, bids: state[:bids] + [ { seat: seat, hops: hops } ], turn: other(seat))
  end

  # "Go for it": I can't beat that bid, prove it. The lowest bidder is now the challenger.
  def call(state, seat)
    require_status!(state, "bidding", "There's nothing to call right now.")
    require_turn!(state, seat)
    raise IllegalMove, "Nobody has bid yet." if state[:bids].empty?

    challenger = state[:bids].last[:seat]
    bump(state, status: "challenge", challenger: challenger, turn: challenger)
  end

  def assert_can_guess!(state, seat)
    require_status!(state, "challenge", "Nobody is building a chain right now.")
    require_seat!(state, seat)
    raise IllegalMove, "Only the challenger builds the chain." unless seat == state[:challenger]
  end

  # `titles` are the shared credits the server verified between the chain's end and the guess.
  def guess(state, seat, person:, titles:, expected_last_id:)
    assert_can_guess!(state, seat)
    raise IllegalMove, "The chain moved on. Try that again." if state[:chain].last[:id] != expected_last_id
    raise IllegalMove, "#{person[:name]} is already in the chain." if state[:chain].any? { |n| n[:id] == person[:id] }
    raise IllegalMove, "That guess doesn't connect." if titles.blank?

    chain = state[:chain] + [ slim(person).merge(via: titles) ]
    hops = chain.size - 1
    bid = state[:bids].last[:hops]
    if person[:id] == state[:target][:id]
      finish(state, chain, winner: seat, kind: "connected", hops: hops)
    elsif hops >= bid
      finish(state, chain, winner: other(seat), kind: "out_of_hops", hops: hops)
    else
      bump(state, chain: chain)
    end
  end

  def give_up(state, seat)
    assert_can_guess!(state, seat)
    finish(state, state[:chain], winner: other(seat), kind: "gave_up", hops: state[:chain].size - 1)
  end

  def hops_remaining(state)
    return unless state[:status] == "challenge"

    state[:bids].last[:hops] - (state[:chain].size - 1)
  end

  def other(seat) = 1 - seat

  # --- helpers ---

  def finish(state, chain, winner:, kind:, hops:)
    scores = state[:scores].dup
    scores[winner] += 1
    result = { winner: winner, kind: kind, hops: hops, bid: state[:bids].last[:hops], challenger: state[:challenger] }
    bump(state, status: "round_over", chain: chain, turn: nil, scores: scores, result: result)
  end

  def bump(state, changes)
    state.merge(changes).merge(version: state[:version] + 1)
  end

  def slim(hash) = hash.to_h.symbolize_keys.slice(:id, :name, :photo_url)

  def truthy?(value) = ActiveModel::Type::Boolean.new.cast(value) || false

  def require_seat!(state, seat)
    raise IllegalMove, "You're watching this room, not playing." unless SEATS.first(state[:players]).include?(seat)
  end

  def require_status!(state, status, message)
    raise IllegalMove, message unless state[:status] == status
  end

  def require_turn!(state, seat)
    require_seat!(state, seat)
    raise IllegalMove, "It's not your turn." unless state[:turn] == seat
  end
end
