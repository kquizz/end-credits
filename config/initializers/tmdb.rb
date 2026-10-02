# Accepts either a v4 read-access token (Bearer) or a v3 api_key; TMDB_API_KEY matches the shell/deploy name used elsewhere.
Rails.application.config.tmdb_api_token =
  Rails.application.credentials.tmdb_api_token || ENV["TMDB_API_TOKEN"] || ENV["TMDB_API_KEY"]
