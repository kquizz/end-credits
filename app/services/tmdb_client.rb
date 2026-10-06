require "faraday"

class TmdbClient
  class Error < StandardError; end
  class NotFound < Error; end

  BASE_URL = "https://api.themoviedb.org/3".freeze
  IMAGE_BASE = "https://image.tmdb.org/t/p".freeze

  SearchResult = Struct.new(:media_type, :id, :title, :year, :poster_url, keyword_init: true)
  Title = Struct.new(:id, :name, :date, keyword_init: true) do
    def year = date&.year
  end
  PersonDetails = Struct.new(:imdb_id, :birthday, :deathday, keyword_init: true)
  PersonResult = Struct.new(:id, :name, :known_for, :photo_url, keyword_init: true)
  Season = Struct.new(:number, :name, :episode_count, keyword_init: true)
  Episode = Struct.new(:number, :name, :date, keyword_init: true)
  CastMember = Struct.new(:person_id, :name, :character, :photo_url, keyword_init: true)
  # One person's whole run on a series: roles is [{ character:, episode_count: }].
  AggregateCastMember = Struct.new(:person_id, :name, :photo_url, :total_episodes, :roles, keyword_init: true)
  Credit = Struct.new(:media_type, :id, :title, :year, :character, :genre_ids, keyword_init: true)

  def initialize(token: Rails.application.config.tmdb_api_token, cache: Rails.cache)
    @token = token
    @cache = cache
  end

  # Movies and TV shows.
  def search(query)
    query = query.to_s.strip
    return [] if query.empty?

    Array(get("/search/multi", query: query)["results"])
      .select { |r| %w[movie tv].include?(r["media_type"]) }
      .map { |r| to_search_result(r) }
  end

  # People, most popular first (TMDb's own ranking), for autocomplete.
  def search_person(query)
    query = query.to_s.strip
    return [] if query.empty?

    Array(get("/search/person", query: query)["results"]).map do |r|
      PersonResult.new(
        id: r["id"], name: r["name"],
        known_for: Array(r["known_for"]).filter_map { |k| k["title"] || k["name"] }.first(3),
        photo_url: image_url(r["profile_path"], "w185")
      )
    end
  end

  def movie(id)
    raw = get("/movie/#{id}")
    Title.new(id: id, name: raw["title"], date: parse_date(raw["release_date"]))
  end

  def movie_cast(id)
    build_cast(get("/movie/#{id}/credits"))
  end

  def tv(id)
    raw = get("/tv/#{id}")
    {
      name: raw["name"],
      seasons: Array(raw["seasons"]).reject { |s| s["season_number"].to_i.zero? }.map do |s|
        Season.new(number: s["season_number"], name: s["name"], episode_count: s["episode_count"])
      end
    }
  end

  def season_episodes(tv_id, season_number)
    Array(get("/tv/#{tv_id}/season/#{season_number}")["episodes"]).map do |e|
      Episode.new(number: e["episode_number"], name: e["name"], date: parse_date(e["air_date"]))
    end
  end

  # Regular cast first, then guest stars.
  def episode_cast(tv_id, season_number, episode_number)
    raw = get("/tv/#{tv_id}/season/#{season_number}/episode/#{episode_number}/credits")
    build_cast("cast" => Array(raw["cast"]) + Array(raw["guest_stars"]))
  end

  # Everyone who ever appeared in a series, with episode counts, in a single request.
  def tv_aggregate_credits(id)
    Array(get("/tv/#{id}/aggregate_credits")["cast"]).map do |m|
      AggregateCastMember.new(
        person_id: m["id"], name: m["name"], photo_url: image_url(m["profile_path"], "w185"),
        total_episodes: m["total_episode_count"].to_i,
        roles: Array(m["roles"]).map { |r| { character: r["character"], episode_count: r["episode_count"].to_i } }
      )
    end
  end

  def person_details(person_id)
    raw = get("/person/#{person_id}")
    PersonDetails.new(imdb_id: raw["imdb_id"].presence,
                      birthday: parse_date(raw["birthday"]), deathday: parse_date(raw["deathday"]))
  end

  # { person_id => PersonDetails or nil }. Cold lookups are one request per person, so fan out; a
  # person TMDb fails on gets nil (and is retried next time, since failures are not cached).
  def people_details(person_ids, concurrency: 8)
    ids = person_ids.uniq
    return {} if ids.empty?

    connection # build the connection once, before the threads race to create it
    queue = Queue.new.tap { |q| ids.each { |id| q << id } }
    results = {}
    lock = Mutex.new

    Array.new([ concurrency, ids.size ].min) do
      Thread.new do
        Rails.application.executor.wrap do
          while (id = next_from(queue))
            details = begin
              person_details(id)
            rescue Error, Faraday::Error => e
              Rails.logger.warn("TMDb person #{id} lookup failed: #{e.message}")
              nil
            end
            lock.synchronize { results[id] = details }
          end
        end
      end
    end.each(&:join)

    ids.to_h { |id| [ id, results[id] ] }
  end

  # { person_id => imdb_id or nil }
  def person_imdb_ids(person_ids, **opts)
    people_details(person_ids, **opts).transform_values { |d| d&.imdb_id }
  end

  # Everything a person has acted in, movies and TV together.
  def person_credits(person_id)
    Array(get("/person/#{person_id}/combined_credits")["cast"]).map do |c|
      Credit.new(
        media_type: c["media_type"], id: c["id"],
        title: c["title"] || c["name"],
        year: year_of(c["release_date"] || c["first_air_date"]),
        character: c["character"], genre_ids: Array(c["genre_ids"])
      )
    end
  end

  private

  def next_from(queue)
    queue.pop(true)
  rescue ThreadError
    nil
  end

  def build_cast(credits)
    Array(credits["cast"]).uniq { |m| m["id"] }.map do |m|
      CastMember.new(person_id: m["id"], name: m["name"], character: m["character"],
                     photo_url: image_url(m["profile_path"], "w185"))
    end
  end

  def to_search_result(raw)
    SearchResult.new(
      media_type: raw["media_type"], id: raw["id"],
      title: raw["title"] || raw["name"],
      year: year_of(raw["release_date"] || raw["first_air_date"]),
      poster_url: image_url(raw["poster_path"], "w185")
    )
  end

  def parse_date(value)
    value.present? ? Date.iso8601(value) : nil
  rescue ArgumentError
    nil
  end

  def year_of(date)
    date.to_s[0, 4].then { |y| y.empty? ? nil : y.to_i }
  end

  def image_url(path, size)
    path && "#{IMAGE_BASE}/#{size}#{path}"
  end

  def get(path, query: {})
    query = { query: query } unless query.is_a?(Hash)
    @cache.fetch("tmdb:#{path}:#{query.sort_by { |k, _| k.to_s }.to_h}", expires_in: 30.days) do
      response = connection.get("#{BASE_URL}#{path}", with_auth(query))
      raise NotFound, "TMDb #{response.status}" if response.status == 404
      raise Error, "TMDb #{response.status}" unless response.success?

      JSON.parse(response.body)
    end
  end

  # v4 read tokens are JWTs and go in a header; v3 keys are plain hex and go in the query string.
  def bearer? = @token.to_s.start_with?("eyJ")

  def with_auth(query)
    bearer? ? query : query.merge(api_key: @token)
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.headers["Authorization"] = "Bearer #{@token}" if bearer?
      f.headers["Accept"] = "application/json"
    end
  end
end
