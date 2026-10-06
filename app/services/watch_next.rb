# Other titles (movies and TV) that several people from a co-star overlap have in common, best first.
# Series-level only, like CostarWeb: "3 of these people were in it", not "together".
class WatchNext
  MAX_PEOPLE = 60
  MIN_PEOPLE = 2
  LIMIT = 25

  Result = Struct.new(:titles, :people_checked, :people_skipped, keyword_init: true) do
    def as_json(*) = { titles: titles, people_checked: people_checked, people_skipped: people_skipped }
  end

  # skip_self / skip_voice / skip_marvel mirror CreditFilter's rules.
  def initialize(tmdb: TmdbClient.new, skip_self: true, skip_voice: true, skip_marvel: false)
    @tmdb = tmdb
    @skip_self = skip_self
    @skip_voice = skip_voice
    @skip_marvel = skip_marvel
  end

  # person_ids is trusted to be best-first (CostarWeb order); only the first MAX_PEOPLE are looked up.
  def call(person_ids, series_ids: [])
    ids = Array(person_ids).uniq.first(MAX_PEOPLE)
    credits = @tmdb.people_credits(ids)
    found = credits.compact
    # Every lookup failing means TMDb is down, not "nothing in common".
    raise TmdbClient::Error, "no credits could be fetched" if found.empty? && ids.any?

    excluded = Array(series_ids).to_set { |id| CreditFilter.title_key("tv", id) }
    filter = credit_filter
    members = Hash.new { |h, k| h[k] = [] }
    found.each do |person_id, list|
      filter.call(list).uniq { |c| CreditFilter.title_key(c.media_type, c.id) }.each do |credit|
        key = CreditFilter.title_key(credit.media_type, credit.id)
        members[key] << [ person_id, credit ] unless excluded.include?(key)
      end
    end

    titles = members.values.select { |m| m.size >= MIN_PEOPLE }.map { |m| title(m) }
    Result.new(titles: rank(titles).first(LIMIT), people_checked: found.size, people_skipped: ids.size - found.size)
  end

  private

  def credit_filter
    marvel = @skip_marvel ? MarvelTitles.new(tmdb: @tmdb).keys : nil
    CreditFilter.new(skip_self: @skip_self, skip_voice: @skip_voice, marvel_ids: marvel)
  end

  def title(members)
    credit = members.first.last
    {
      media_type: credit.media_type, id: credit.id, title: credit.title, year: credit.year,
      poster_url: members.filter_map { |_, c| c.poster_url }.first,
      member_count: members.size,
      total_episodes: members.sum { |_, c| c.episode_count.to_i },
      popularity: members.map { |_, c| c.popularity.to_f }.max,
      person_ids: members.map(&:first)
    }
  end

  def rank(titles)
    titles.sort_by { |t| [ -t[:member_count], -t[:total_episodes], -t[:popularity], -t[:year].to_i, t[:title].to_s ] }
  end
end
