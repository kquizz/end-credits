class DegreesController < ApplicationController
  MAX_SUGGESTIONS = 8

  # Later handlers win, so the specific NotFound must come after its parent Error.
  rescue_from TmdbClient::Error do
    render_error "TMDb isn't responding right now. Try again in a moment.", :bad_gateway
  end
  rescue_from TmdbClient::NotFound do
    render_error "TMDb doesn't know that person.", :not_found
  end

  # `/degrees?start=31&target=5064&tier=easy` is a shareable game. Without a usable pair we draw a
  # random one (from the tier, if given) and redirect so the address bar is always shareable.
  def index
    @tier = TargetList::TIERS.include?(params[:tier]) ? params[:tier] : nil
    @tiers = TargetList::TIERS
    start_id = params[:start].to_i
    target_id = params[:target].to_i
    return redirect_to_new_game if start_id.zero? || target_id.zero? || start_id == target_id

    @start = tmdb.person(start_id)
    @target = tmdb.person(target_id)
  rescue TmdbClient::NotFound
    redirect_to_new_game
  end

  # Autocomplete: TMDb ranks person search by popularity already.
  def people
    results = tmdb.search_person(params[:q]).first(MAX_SUGGESTIONS)
    render json: results.map { |p| p.to_h.slice(:id, :name, :photo_url, :known_for) }
  end

  # Can the guess join the end of the chain? Wrong guesses are a normal 200 with ok: false.
  def guess
    last_id = params[:chain_last_id].to_i
    guess_id = params[:guess_id].to_i
    if last_id.zero? || guess_id.zero?
      return render json: { ok: false, message: "Pick someone from the list." }, status: :unprocessable_content
    end

    person = tmdb.person(guess_id)
    if ([ last_id ] + int_ids(params[:chain])).include?(guess_id)
      return render json: { ok: false, message: "#{person.name} is already in your chain." }
    end

    titles = ConnectionCheck.new(client: tmdb).call(last_id, guess_id, rules)
    if titles.empty?
      render json: { ok: false, message: "#{person.name} hasn't shared a credit with #{tmdb.person(last_id).name}, under these rules." }
    else
      render json: { ok: true, titles: titles, person: { id: person.id, name: person.name, photo_url: person.photo_url } }
    end
  end

  private

  def redirect_to_new_game
    start, target = TargetList.new.random_pair(tier: @tier)
    redirect_to degrees_path({ start: start.id, target: target.id, tier: @tier }.compact)
  end

  def rules
    { skip_self: flag(:skip_self, true), skip_voice: flag(:skip_voice, true), skip_marvel: flag(:skip_marvel, false),
      movies_only: flag(:movies_only, false), years: years }
  end

  # year_from / year_to, either optional; swapped if given backwards.
  def years
    from = params[:year_from].presence&.to_i
    to = params[:year_to].presence&.to_i
    return unless from || to

    Range.new(*[ from || 0, to || 9999 ].minmax)
  end

  def int_ids(value) = Array(value).map(&:to_i).reject(&:zero?).uniq

  def flag(name, default)
    params.key?(name) ? ActiveModel::Type::Boolean.new.cast(params[name]) : default
  end

  def render_error(message, status)
    if request.format.json?
      render json: { ok: false, message: message }, status: status
    else
      render plain: message, status: status
    end
  end

  def tmdb = @tmdb ||= TmdbClient.new
end
