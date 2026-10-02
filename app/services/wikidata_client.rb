require "faraday"

# Maps IMDb person IDs to their English Wikipedia article title via Wikidata's IMDb ID property (P345).
# That link is exact, unlike matching on names. Failures degrade to "no match" rather than raising.
class WikidataClient
  SPARQL = "https://query.wikidata.org/sparql".freeze
  USER_AGENT = "end-credits/0.1 (https://credits.kquizz.com)".freeze
  ARTICLE_PREFIX = "https://en.wikipedia.org/wiki/".freeze
  BATCH_SIZE = 50

  def initialize(cache: Rails.cache)
    @cache = cache
  end

  # { "nm0000158" => "Tom Hanks" } for every ID that has an English Wikipedia article.
  def wikipedia_titles(imdb_ids)
    imdb_ids = Array(imdb_ids).compact.uniq.grep(/\Anm\d+\z/)
    imdb_ids.each_slice(BATCH_SIZE).reduce({}) { |acc, slice| acc.merge(fetch(slice)) }
  end

  private

  def fetch(imdb_ids)
    query = <<~SPARQL
      SELECT ?imdb ?article WHERE {
        VALUES ?imdb { #{imdb_ids.map { |id| %("#{id}") }.join(" ")} }
        ?item wdt:P345 ?imdb .
        ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> .
      }
    SPARQL

    bindings = @cache.fetch("wd:imdb:#{imdb_ids.sort.join(',')}", expires_in: 30.days) do
      response = connection.get(SPARQL, query: query, format: "json")
      raise "Wikidata #{response.status}" unless response.success?

      JSON.parse(response.body).dig("results", "bindings")
    end

    Array(bindings).to_h { |b| [ b.dig("imdb", "value"), title_from(b.dig("article", "value")) ] }
  rescue Faraday::Error, JSON::ParserError, RuntimeError => e
    Rails.logger.warn("Wikidata lookup failed: #{e.message}")
    {}
  end

  def title_from(url)
    CGI.unescape(url.delete_prefix(ARTICLE_PREFIX)).tr("_", " ")
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = "application/sparql-results+json"
    end
  end
end
