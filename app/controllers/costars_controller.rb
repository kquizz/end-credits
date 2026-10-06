class CostarsController < ApplicationController
  MIN_SERIES = 2
  MAX_PRELOAD = 8
  # A search hit with no poster and less popularity than this is almost always a stub or a remake nobody watched.
  JUNK_POPULARITY = 2.0

  # Later handlers win, so the specific NotFound must come after its parent Error.
  rescue_from TmdbClient::Error do
    render json: { error: "TMDb isn't responding right now. Try again in a moment." }, status: :bad_gateway
  end
  rescue_from TmdbClient::NotFound do
    render json: { error: "TMDb doesn't know one of those series." }, status: :not_found
  end

  # `/costars?ids[]=81723&ids[]=1435` is a shareable link: the chips are filled in server-side
  # and the page runs the overlap on load.
  def index
    @preloaded = Array(params[:ids]).map(&:to_i).reject(&:zero?).uniq.first(MAX_PRELOAD).filter_map { |id| preload(id) }
  end

  # Series-only title search for the picker, most popular first, without poster-less stubs.
  def search
    results = tmdb.search(params[:q]).select { |r| r.media_type == "tv" && !junk?(r) }
    render json: results.sort_by { |r| -r.popularity.to_f }.map { |r| r.to_h.slice(:id, :title, :year, :poster_url) }
  end

  def overlap
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?).uniq
    if ids.size < MIN_SERIES
      return render json: { error: "Pick at least #{MIN_SERIES} series." }, status: :unprocessable_content
    end

    render json: CostarWeb.new(tmdb: tmdb).call(ids)
  end

  # Titles several of the given people (best-first) share. Lazy on purpose: one cached credits
  # lookup per person, so the page only calls it when asked.
  def watch_next
    people = int_ids(params[:ids])
    if people.size < WatchNext::MIN_PEOPLE
      return render json: { error: "Need at least #{WatchNext::MIN_PEOPLE} people." }, status: :unprocessable_content
    end

    render json: WatchNext.new(tmdb: tmdb, skip_self: flag(:skip_self, true), skip_voice: flag(:skip_voice, true),
                               skip_marvel: flag(:skip_marvel, false)).call(people, series_ids: int_ids(params[:series]))
  end

  private

  def int_ids(value) = Array(value).map(&:to_i).reject(&:zero?).uniq

  def flag(name, default)
    params.key?(name) ? ActiveModel::Type::Boolean.new.cast(params[name]) : default
  end

  # A series TMDb doesn't know (or can't be reached for) is skipped rather than breaking the page.
  def preload(id)
    { id: id, title: tmdb.tv(id)[:name] }
  rescue TmdbClient::Error
    nil
  end

  def junk?(result)
    result.poster_url.nil? && result.popularity && result.popularity < JUNK_POPULARITY
  end

  def tmdb = @tmdb ||= TmdbClient.new
end
