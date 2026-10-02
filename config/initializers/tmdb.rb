Rails.application.config.tmdb_api_token =
  Rails.application.credentials.tmdb_api_token || ENV["TMDB_API_TOKEN"]
