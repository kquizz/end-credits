# Streams a Six Degrees room's public state to everyone looking at it, players and spectators alike.
# It is read-only: all moves are HTTP POSTs (Degrees::RoomsController), which broadcast the result.
class RoomChannel < ApplicationCable::Channel
  def subscribed
    room = Room.find_by_code(params[:code])
    return reject unless room

    stream_from room.stream_name
    # Whoever subscribes (including after a reconnect) starts from the current state, not a stale page.
    transmit(room.public_state.merge(you: room.seat_for(connection.seats[room.code])))
  end
end
