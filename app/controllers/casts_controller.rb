class CastsController < ApplicationController
  # Later handlers win, so the specific NotFound must come after its parent Error.
  rescue_from TmdbClient::Error, with: :tmdb_unavailable
  rescue_from TmdbClient::NotFound, with: -> { head :not_found }

  def index
    @query = params[:q].to_s
    @results = @query.present? ? tmdb.search(@query) : []
  end

  def movie
    @movie = tmdb.movie(params[:id])
    @cast = tmdb.movie_cast(params[:id])
    @table_params = { kind: "movie", id: params[:id] }
  end

  def show
    @show = tmdb.tv(params[:id])
  end

  def season
    @show = tmdb.tv(params[:id])
    @season = params[:season]
    @episodes = tmdb.season_episodes(params[:id], @season)
  end

  def episode
    @show = tmdb.tv(params[:id])
    @season = params[:season]
    @episode = tmdb.season_episodes(params[:id], @season).find { |e| e.number.to_s == params[:episode] }
    return head :not_found unless @episode

    @cast = tmdb.episode_cast(params[:id], @season, params[:episode])
    @table_params = { kind: "episode", id: params[:id], season: @season, episode: params[:episode] }
  end

  # Lazy-loaded by the movie/episode pages: the same cast, now with EGOT cells filled in.
  def table
    cast = table_cast
    @rows = CastEgotLookup.new(tmdb: tmdb).call(cast)
  end

  private

  def table_cast
    case params[:kind]
    when "movie" then tmdb.movie_cast(params[:id])
    when "episode" then tmdb.episode_cast(params[:id], params[:season], params[:episode])
    else raise TmdbClient::NotFound
    end
  end

  def tmdb
    @tmdb ||= TmdbClient.new
  end

  def tmdb_unavailable
    render plain: "TMDb isn't responding right now. Try again in a moment.", status: :bad_gateway
  end
end
