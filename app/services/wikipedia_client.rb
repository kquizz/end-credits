require "faraday"

class WikipediaClient
  API = "https://en.wikipedia.org/w/api.php".freeze
  REST_SEARCH = "https://en.wikipedia.org/w/rest.php/v1/search/page".freeze
  USER_AGENT = "end-credits/0.1 (https://credits.kquizz.com)".freeze

  # MediaWiki caps multi-title queries at 50; category lists paginate across pages, so chunk smaller.
  BATCH_SIZE = 20
  MAX_CONTINUES = 10

  Candidate = Struct.new(:title, :description, :thumbnail_url, keyword_init: true)
  Profile = Struct.new(:title, :qid, :thumbnail_url, :categories, keyword_init: true)

  def initialize(cache: Rails.cache)
    @cache = cache
  end

  def search(query)
    query = query.to_s.strip
    return [] if query.empty?

    payload = get_json(REST_SEARCH, q: query, limit: 8)
    Array(payload["pages"]).map do |page|
      Candidate.new(
        title: page["title"],
        description: page["description"],
        thumbnail_url: page.dig("thumbnail", "url")
      )
    end
  end

  def profile(title)
    profiles([ title ])[title] || Profile.new(title: title, categories: [])
  end

  # Batched lookup: returns { requested_title => Profile } for every title Wikipedia resolved.
  # Titles are normalized and redirects followed, but results are keyed by what the caller asked for.
  def profiles(titles)
    titles = Array(titles).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    titles.each_slice(BATCH_SIZE).reduce({}) { |acc, slice| acc.merge(fetch_profiles(slice)) }
  end

  private

  def fetch_profiles(titles)
    pages = {}
    redirected = {}
    continuation = {}

    MAX_CONTINUES.times do
      payload = get_json(API, profile_params(titles).merge(continuation))
      merge_pages!(pages, payload.dig("query", "pages"))
      track_redirects!(redirected, payload["query"])
      continuation = (payload["continue"] || break).transform_keys(&:to_sym)
    end

    titles.each_with_object({}) do |requested, result|
      resolved = redirected.fetch(requested, requested)
      page = pages.values.find { |p| p["title"] == resolved }
      result[requested] = build_profile(page, requested) if page && !page.key?("missing")
    end
  end

  def profile_params(titles)
    { action: "query", format: "json", redirects: 1,
      prop: "categories|pageprops|pageimages",
      ppprop: "wikibase_item", piprop: "thumbnail", pithumbsize: 200,
      cllimit: 500, clshow: "!hidden", titles: titles.join("|") }
  end

  # Continuation responses repeat each page with only the next slice of categories.
  def merge_pages!(pages, incoming)
    (incoming || {}).each do |id, page|
      existing = pages[id]
      if existing
        existing["categories"] = Array(existing["categories"]) + Array(page["categories"])
      else
        pages[id] = page
      end
    end
  end

  def track_redirects!(redirected, query)
    normalized = Array(query&.dig("normalized")).to_h { |n| [ n["from"], n["to"] ] }
    redirects = Array(query&.dig("redirects")).to_h { |r| [ r["from"], r["to"] ] }
    normalized.each { |from, to| redirected[from] = redirects.fetch(to, to) }
    redirects.each { |from, to| redirected[from] ||= to }
  end

  def build_profile(page, requested)
    Profile.new(
      title: page["title"] || requested,
      qid: page.dig("pageprops", "wikibase_item"),
      thumbnail_url: page.dig("thumbnail", "source"),
      categories: Array(page["categories"]).map { |c| c["title"] }
    )
  end

  def get_json(url, params)
    @cache.fetch("wp:#{url}:#{params.sort_by { |k, _| k.to_s }.to_h}", expires_in: 7.days) do
      response = connection.get(url, params)
      raise "MediaWiki #{response.status}" unless response.success?

      JSON.parse(response.body)
    end
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = "application/json"
    end
  end
end
