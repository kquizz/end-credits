class CostarsController < ApplicationController
  MIN_SERIES = 2

  # Later handlers win, so the specific NotFound must come after its parent Error.
  rescue_from TmdbClient::Error do
    render json: { error: "TMDb isn't responding right now. Try again in a moment." }, status: :bad_gateway
  end
  rescue_from TmdbClient::NotFound do
    render json: { error: "TMDb doesn't know one of those series." }, status: :not_found
  end

  def index; end

  # Series-only title search for the picker.
  def search
    results = tmdb.search(params[:q]).select { |r| r.media_type == "tv" }
    render json: results.map { |r| r.to_h.slice(:id, :title, :year, :poster_url) }
  end

  def overlap
    ids = Array(params[:ids]).map(&:to_i).reject(&:zero?).uniq
    if ids.size < MIN_SERIES
      return render json: { error: "Pick at least #{MIN_SERIES} series." }, status: :unprocessable_content
    end

    render json: CostarWeb.new(tmdb: tmdb).call(ids)
  end

  private

  def tmdb = @tmdb ||= TmdbClient.new
end
