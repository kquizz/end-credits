# One live Six Degrees game between two players. `state` is the RoomGame state machine's hash and
# `players` is [{ token, name }] by seat; tokens are secrets and never leave this class.
class Room < ApplicationRecord
  CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ".chars.freeze # no 0/O/1/I/L
  CODE_LENGTH = 6
  MAX_NAME = 24
  IDLE_LIMIT = 24.hours

  validates :code, presence: true, uniqueness: true

  scope :idle, -> { where(updated_at: ...IDLE_LIMIT.ago) }

  # Creates a room with the creator in seat 0. Returns [room, token].
  def self.open!(creator_name)
    attempts = 0
    begin
      token = SecureRandom.urlsafe_base64(24)
      room = create!(code: random_code, state: RoomGame.initial,
                     players: [ { token: token, name: clean_name(creator_name, 1) } ])
      [ room, token ]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      retry if (attempts += 1) < 5
      raise
    end
  end

  def self.random_code = Array.new(CODE_LENGTH) { CODE_ALPHABET.sample }.join

  def self.find_by_code(code) = find_by(code: code.to_s.upcase)

  def self.purge_idle! = idle.delete_all

  def self.clean_name(name, seat_number)
    name.to_s.squish.first(MAX_NAME).presence || "Player #{seat_number}"
  end

  def seat_for(token)
    return if token.blank?

    players.index { |p| ActiveSupport::SecurityUtils.secure_compare(p["token"].to_s, token.to_s) }
  end

  def full? = players.size >= 2

  # Seats the second player. Returns their token; raises RoomGame::IllegalMove when the room is full.
  def join!(name)
    token = SecureRandom.urlsafe_base64(24)
    with_lock do
      self.state = RoomGame.join(game).to_h
      self.players = players + [ { token: token, name: self.class.clean_name(name, 2) } ]
      save!
    end
    broadcast_state
    token
  end

  def rename!(seat, name)
    with_lock do
      self.players = players.each_with_index.map { |p, i| i == seat ? p.merge("name" => self.class.clean_name(name, seat + 1)) : p }
      touch_state
      save!
    end
    broadcast_state
  end

  # Runs a state-machine move under a row lock and broadcasts the result. The block gets the current
  # game state and returns the next one; an IllegalMove raised inside rolls everything back.
  def transition!
    with_lock do
      self.state = yield(game)
      save!
    end
    broadcast_state
    self
  end

  def game = state.deep_symbolize_keys

  def rules = game[:rules]

  def stream_name = "degrees_room:#{code}"

  # What every connected screen receives. No tokens, nothing viewer-specific.
  def public_state
    g = game
    g.slice(:status, :round_number, :opener, :turn, :bids, :challenger, :chain, :start, :target, :scores, :result,
            :rules, :version).merge(
      code: code,
      players: players.each_with_index.map { |p, seat| { seat: seat, name: p["name"] } },
      hops_remaining: RoomGame.hops_remaining(g),
      max_hops: g[:bids].last&.fetch(:hops)
    )
  end

  def broadcast_state
    ActionCable.server.broadcast(stream_name, public_state)
  end

  private

  # A rename changes what screens show, so it must also bump the version clients use to drop stale pushes.
  def touch_state
    self.state = state.merge("version" => state["version"].to_i + 1)
  end
end
