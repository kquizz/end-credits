module ApplicationCable
  # No user model: a browser's seats live in a signed cookie ({ room code => seat token }). The channel
  # picks the entry for the room it's subscribing to, and spectators simply have none.
  class Connection < ActionCable::Connection::Base
    def seats
      @seats ||= cookies.signed[Degrees::RoomsController::SEATS_COOKIE].then { |value| value.is_a?(Hash) ? value : {} }
    end
  end
end
