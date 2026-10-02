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

  get "cast", to: "casts#index", as: :cast
  get "cast/table", to: "casts#table", as: :cast_table
  get "cast/movies/:id", to: "casts#movie", as: :cast_movie
  get "cast/shows/:id", to: "casts#show", as: :cast_show
  get "cast/shows/:id/seasons/:season", to: "casts#season", as: :cast_season
  get "cast/shows/:id/seasons/:season/episodes/:episode", to: "casts#episode", as: :cast_episode
end
