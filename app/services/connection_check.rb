# Do two people share a credit under the active rules? Returns the shared titles (best-known first),
# or an empty array. Two cached credit lookups and an intersection by (media_type, id); the same
# CreditFilter rules the Co-star Web uses.
#
# rules: skip_self (default true), skip_voice (default true), skip_marvel, movies_only, years (a Range).
class ConnectionCheck
  DEFAULT_RULES = { skip_self: true, skip_voice: true, skip_marvel: false, movies_only: false, years: nil }.freeze

  def initialize(client: TmdbClient.new, marvel_ids: nil)
    @client = client
    @marvel_ids = marvel_ids
  end

  def call(person_a_id, person_b_id, rules = {})
    filter = credit_filter(DEFAULT_RULES.merge(rules.to_h.symbolize_keys))
    mine = by_title(filter, person_a_id)
    theirs = by_title(filter, person_b_id)

    (mine.keys & theirs.keys).map { |key| shared_title(mine[key], theirs[key]) }
      .sort_by { |t| [ -t[:popularity].to_f, -t[:year].to_i, t[:title].to_s ] }
      .map { |t| t.except(:popularity) }
  end

  private

  def credit_filter(rules)
    marvel = rules[:skip_marvel] ? (@marvel_ids ||= MarvelTitles.new(tmdb: @client).keys) : nil
    CreditFilter.new(skip_self: rules[:skip_self], skip_voice: rules[:skip_voice], marvel_ids: marvel,
                     movies_only: rules[:movies_only], years: rules[:years])
  end

  def by_title(filter, person_id)
    filter.call(@client.person_credits(person_id)).group_by { |c| CreditFilter.title_key(c.media_type, c.id) }
      .transform_values(&:first)
  end

  def shared_title(a, b)
    best = [ a, b ].max_by { |c| c.popularity.to_f }
    { id: a.id, title: a.title, year: a.year, media_type: a.media_type,
      poster_url: a.poster_url || b.poster_url, popularity: best.popularity }
  end
end
