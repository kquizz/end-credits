# The set of Marvel movies and shows, as CreditFilter title keys ("movie:299534"). Built from three
# TMDb /discover queries per media type instead of a lookup per title:
#   production company 420 (Marvel Studios), 38679 (Marvel Television, TV only) and keyword 180547
#   ("marvel cinematic universe (mcu)"). All three ids were checked against the live API.
# A film made by another studio without the MCU keyword (Sony's X-Men, Fox's Fantastic Four) is not
# caught: this is "Marvel Studios / MCU", not every Marvel character. Pages cache for 30 days.
class MarvelTitles
  FILTERS = {
    "movie" => [ { with_companies: 420 }, { with_keywords: 180_547 } ],
    "tv" => [ { with_companies: 420 }, { with_companies: 38_679 }, { with_keywords: 180_547 } ]
  }.freeze

  def initialize(tmdb: TmdbClient.new)
    @tmdb = tmdb
  end

  def keys
    @keys ||= FILTERS.flat_map do |media_type, filters|
      filters.flat_map { |f| @tmdb.discover_ids(media_type, **f) }.map { |id| CreditFilter.title_key(media_type, id) }
    end.to_set
  end
end
