# Live two-player Six Degrees. The room page and every move live here; the state machine
# (RoomGame) decides what's legal and RoomChannel pushes the result to both screens.
module Degrees
  class RoomsController < ApplicationController
    SEATS_COOKIE = :degrees_seats
    MAX_REMEMBERED_ROOMS = 10

    rescue_from RoomGame::IllegalMove do |e|
      render json: { ok: false, message: e.message, state: @room&.public_state, you: @seat }, status: :unprocessable_content
    end
    rescue_from TmdbClient::Error do
      render json: { ok: false, message: "TMDb isn't responding right now. Try again in a moment." }, status: :bad_gateway
    end
    rescue_from TmdbClient::NotFound do
      render json: { ok: false, message: "TMDb doesn't know that person." }, status: :not_found
    end

    before_action :load_room, except: :create
    before_action :require_seat, except: %i[create show join]

    def create
      room, token = Room.open!(params[:name])
      remember_seat(room.code, token)
      redirect_to degrees_room_path(room.code)
    end

    def show
      respond_to do |format|
        format.html { @can_join = @seat.nil? && !@room.full? }
        format.json { render_state }
      end
    end

    def join
      if @seat.nil? && !@room.full?
        token = @room.join!(params[:name])
        remember_seat(@room.code, token)
        @seat = @room.reload.seat_for(token)
      end
      respond_to do |format|
        format.html { redirect_to degrees_room_path(@room.code) }
        format.json { render_state }
      end
    end

    def set_name
      @room.rename!(@seat, params[:name])
      render_state
    end

    def set_rules
      @room.transition! { |g| RoomGame.set_rules(g, @seat, params.permit(rules: RoomGame::RULE_DEFAULTS.keys).fetch(:rules, {}).to_h) }
      render_state
    end

    def bid
      @room.transition! { |g| RoomGame.bid(g, @seat, params[:hops]) }
      render_state
    end

    def challenge
      @room.transition! { |g| RoomGame.call(g, @seat) }
      render_state
    end

    def give_up
      @room.transition! { |g| RoomGame.give_up(g, @seat) }
      render_state
    end

    # Idempotent: the client says which round it was looking at, and if that round has already moved on
    # (the other player clicked first) we just return the current state without drawing another pair.
    def next_round
      expected = params[:round_number].to_i
      if RoomGame.startable?(@room.game, expected)
        pair = PairGenerator.new(client: tmdb, rules: @room.rules).call # slow-ish, so outside the row lock
        @room.transition! do |g|
          RoomGame.start_round(g, @seat, expected_round: expected, start: pair.start, target: pair.target)
        end
      end
      render_state
    end

    # Wrong guesses are a normal 200 with ok: false (nothing is spent). The server does the checking.
    def guess
      game = @room.game
      RoomGame.assert_can_guess!(game, @seat)
      guess_id = params[:guess_id].to_i
      return render(json: { ok: false, message: "Pick someone from the list." }, status: :unprocessable_content) if guess_id.zero?

      last = game[:chain].last
      person = tmdb.person(guess_id)
      return render_miss("#{person.name} is already in the chain.") if game[:chain].any? { |n| n[:id] == person.id }

      titles = ConnectionCheck.new(client: tmdb).call(last[:id], person.id, game[:rules])
      return render_miss("#{person.name} hasn't shared a credit with #{last[:name]}, under these rules.") if titles.empty?

      guessed = { id: person.id, name: person.name, photo_url: person.photo_url }
      @room.transition! { |g| RoomGame.guess(g, @seat, person: guessed, titles: titles, expected_last_id: last[:id]) }
      render_state
    end

    private

    def load_room
      @room = Room.find_by_code(params[:code])
      @seat = @room&.seat_for(seats[@room.code]) if @room
      return if @room

      respond_to do |format|
        format.html { render plain: "That room doesn't exist (rooms are cleared after a day of silence).", status: :not_found }
        format.json { render json: { ok: false, message: "Room not found." }, status: :not_found }
      end
    end

    def require_seat
      render json: { ok: false, message: "You're watching this room, not playing." }, status: :forbidden unless @seat
    end

    def render_state(extra = {})
      render json: { ok: true, state: @room.reload.public_state, you: @seat }.merge(extra)
    end

    def render_miss(message)
      render_state(ok: false, message: message)
    end

    def seats = cookies.signed[SEATS_COOKIE].then { |value| value.is_a?(Hash) ? value : {} }

    def remember_seat(code, token)
      remembered = seats.except(code).merge(code => token).to_a.last(MAX_REMEMBERED_ROOMS).to_h
      cookies.signed[SEATS_COOKIE] = { value: remembered, expires: 30.days, httponly: true, same_site: :lax }
    end

    def tmdb = @tmdb ||= TmdbClient.new
  end
end
