Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  get "costars", to: "costars#index", as: :costars
  get "costars/search", to: "costars#search", as: :costars_search, defaults: { format: :json }
  get "costars/overlap", to: "costars#overlap", as: :costars_overlap, defaults: { format: :json }
  get "costars/watch_next", to: "costars#watch_next", as: :costars_watch_next, defaults: { format: :json }

  get "degrees", to: "degrees#index", as: :degrees
  get "degrees/people", to: "degrees#people", as: :degrees_people, defaults: { format: :json }
  get "degrees/guess", to: "degrees#guess", as: :degrees_guess, defaults: { format: :json }

  # Live two-player rooms. Moves are POSTs that answer with the new state JSON; RoomChannel pushes it too.
  post "degrees/rooms", to: "degrees/rooms#create", as: :degrees_rooms
  get "degrees/rooms/:code", to: "degrees/rooms#show", as: :degrees_room
  %w[join set_name set_rules bid challenge give_up next_round guess].each do |action|
    post "degrees/rooms/:code/#{action}", to: "degrees/rooms##{action}", as: "degrees_room_#{action}"
  end

  # The EGOT table and the ages table share the same pickers; `tool` picks the table.
  { "cast" => "egot", "ages" => "ages" }.each do |prefix, tool|
    defaults tool: tool do
      get prefix, to: "casts#index", as: prefix
      get "#{prefix}/table", to: "casts#table", as: "#{prefix}_table"
      get "#{prefix}/movies/:id", to: "casts#movie", as: "#{prefix}_movie"
      get "#{prefix}/shows/:id", to: "casts#show", as: "#{prefix}_show"
      get "#{prefix}/shows/:id/seasons/:season", to: "casts#season", as: "#{prefix}_season"
      get "#{prefix}/shows/:id/seasons/:season/episodes/:episode", to: "casts#episode", as: "#{prefix}_episode"
    end
  end
end
