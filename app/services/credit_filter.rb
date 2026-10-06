# Pure rules for dropping credits that make poor "shared work" (no I/O). Shared by the Co-star Web's
# watch-next list and, later, the six-degrees game. Works on TmdbClient::Credit-shaped objects.
#
# Marvel can't be decided from a credit alone, so the caller passes `marvel_ids:` (see MarvelTitles).
class CreditFilter
  ANIMATION_GENRE = 16
  # Talk (10767) and News (10763): a blank character there is the person appearing as themselves.
  TALK_GENRES = [ 10767, 10763 ].freeze

  SELF_WORDS = "self|himself|herself|themselves|themself".freeze
  # "Self - Host", "Himself (Guest)" and friends; anything else after the word means it's a name.
  SELF_ROLE_WORDS = "host|co-host|guest|presenter|performer|narrator|contestant|panelist|judge|interviewee|" \
                    "winner|nominee|honoree|musical guest|guest host|cameo".freeze
  SELF_PATTERN = /\A(?:#{SELF_WORDS})(?:\s+(?:#{SELF_ROLE_WORDS}))?\z/
  BARE_APPEARANCE = /\A(?:host|guest|presenter|guest host|co-host)\z/
  ARCHIVE_PATTERN = /\barchive\s+(?:footage|material|sound|audio|recording)/i
  VOICE_PATTERN = /\([^)]*\bvoice\b[^)]*\)/i
  SEGMENT_SPLIT = %r{\s*(?:/|,|;|\s-\s|\s–\s|\band\b|&)\s*}i

  def initialize(skip_self: true, skip_voice: false, marvel_ids: nil, movies_only: false, years: nil)
    @skip_self = skip_self
    @skip_voice = skip_voice
    @marvel_ids = marvel_ids # nil = Marvel rule off; otherwise a set of "movie:123" / "tv:45" keys
    @movies_only = movies_only
    @years = years
  end

  def self.title_key(media_type, id) = "#{media_type}:#{id}"

  def call(credits) = credits.select { |credit| keep?(credit) }

  def keep?(credit)
    return false if @movies_only && credit.media_type != "movie"
    return false if @years && !@years.cover?(credit.year)
    return false if @skip_self && self_credit?(credit)
    return false if @skip_voice && voice_credit?(credit)
    return false if @marvel_ids && @marvel_ids.include?(self.class.title_key(credit.media_type, credit.id))

    true
  end

  def self_credit?(credit)
    character = credit.character.to_s
    return true if character.match?(ARCHIVE_PATTERN)
    return talk_genre?(credit) if character.strip.empty?

    segments(character).any? { |s| s.match?(SELF_PATTERN) || s.match?(BARE_APPEARANCE) }
  end

  def voice_credit?(credit)
    credit.character.to_s.match?(VOICE_PATTERN) || Array(credit.genre_ids).include?(ANIMATION_GENRE)
  end

  private

  def talk_genre?(credit) = (Array(credit.genre_ids) & TALK_GENRES).any?

  # "Self - Host (uncredited)" and "Himself / Herself" => each part, lowercase, parentheticals removed.
  def segments(character)
    character.downcase.gsub(/\([^)]*\)|\[[^\]]*\]/, " ").split(SEGMENT_SPLIT).map { |s| s.squish }.reject(&:empty?)
  end
end
