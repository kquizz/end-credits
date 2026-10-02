# Turns a TMDb cast list into EGOT rows: TMDb person -> IMDb ID -> Wikipedia article -> award categories.
# A row's status is nil when the person could not be tied to an article ("unknown", not "no awards").
class CastEgotLookup
  Row = Struct.new(:member, :wikipedia_title, :status, keyword_init: true) do
    def matched? = !status.nil?
  end

  def initialize(tmdb: TmdbClient.new, wikidata: WikidataClient.new, wikipedia: WikipediaClient.new)
    @tmdb = tmdb
    @wikidata = wikidata
    @wikipedia = wikipedia
  end

  def call(cast)
    imdb_ids = @tmdb.person_imdb_ids(cast.map(&:person_id))
    titles = @wikidata.wikipedia_titles(imdb_ids.values)
    profiles = @wikipedia.profiles(titles.values)

    cast.map do |member|
      title = titles[imdb_ids[member.person_id]]
      profile = profiles[title]
      Row.new(member: member, wikipedia_title: title,
              status: profile && AwardClassifier.call(profile.categories))
    end
  end
end
