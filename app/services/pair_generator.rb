# Draws a Six Degrees pair that is guaranteed reachable. TMDb has no path API, so instead of searching
# for a path between two random people we WALK one: start from a popular actor, hop k times through
# well-known shared titles (picking a top-billed co-star each time), and call the last person the
# target. The walk itself is a valid start -> target chain of at most k hops under the room's rules,
# and every hop is re-verified with ConnectionCheck so a voice/Self/Marvel credit can't sneak in.
#
# k stays on the server (it's the walk length, not the player's par). Cost is a handful of cached
# TMDb calls per hop. If every attempt fails (TMDb down, thin data) we fall back to a curated pair,
# which is NOT guaranteed reachable under unusual rules; `Pair#fallback` says so.
class PairGenerator
  Pair = Struct.new(:start, :target, :hops, :walk, :fallback, keyword_init: true) do
    # "Tom Hanks -[Big]-> Robert Loggia -[...]-> ..." for logs.
    def describe
      return "#{start[:name]} -> #{target[:name]} (curated fallback)" if fallback

      walk.map { |step| step[:title] ? "-[#{step[:title]}]-> #{step[:person][:name]}" : step[:person][:name] }.join(" ")
    end
  end

  HOPS = (3..5)
  POPULAR_PAGES = (1..5)
  MIN_CREDITS = 15      # credits surviving the rules; keeps thin filmographies out of the walk
  WELL_KNOWN_VOTES = 1000 # a title with this many TMDb votes is one people have heard of
  MIN_NOTABLE = 4       # well-known titles a walked-through person needs
  TARGET_NOTABLE = 8    # ...and the target, who has to be recognizable by name, needs more
  TOP_TITLES = 12       # hop through one of the person's 12 best-known titles
  TITLES_PER_HOP = 4
  TOP_BILLED = 10
  CANDIDATES_PER_TITLE = 4
  # Documentary, news, talk and reality: huge casts of "themselves" that connect everyone to everyone.
  BORING_GENRES = [ 99, 10_763, 10_764, 10_767 ].freeze

  def initialize(client: TmdbClient.new, rules: {}, targets: TargetList.new, random: Random.new,
                 attempts: 6, hops: HOPS, min_credits: MIN_CREDITS, min_notable: MIN_NOTABLE, target_notable: TARGET_NOTABLE, logger: Rails.logger)
    @client = client
    @rules = ConnectionCheck::DEFAULT_RULES.merge(rules.to_h.symbolize_keys)
    @targets = targets
    @random = random
    @attempts = attempts
    @hops = hops
    @min_credits = min_credits
    @min_notable = min_notable
    @target_notable = target_notable
    @logger = logger
  end

  def call
    @attempts.times do
      pair = attempt
      next unless pair

      @logger.info("PairGenerator: #{pair.describe}")
      return pair
    rescue TmdbClient::Error, Faraday::Error => e
      @logger.warn("PairGenerator attempt failed: #{e.message}")
    end
    fallback
  end

  private

  def attempt
    hops = @random.rand(@hops)
    start = pick_start or return
    walk = [ { person: start, title: nil } ]
    hops.times do
      step = hop(walk) or return
      walk << step
    end
    target = walk.last[:person]
    return unless presentable?(target, @target_notable)
    # A direct shared credit would make it a one-hop gimme.
    return if connected?(start[:id], target[:id])

    Pair.new(start: start, target: target, hops: hops, walk: walk, fallback: false)
  end

  # --- picking people ---

  def pick_start
    pool = popular_pool + @targets.all.map { |t| { id: t.id, name: t.name, photo_url: nil } }
    5.times do
      person = pool.sample(random: @random)
      person = hydrate(person)
      return person if presentable?(person)
    end
    nil
  end

  # TMDb's popular-people chart, five pages. Cached by the client, so only the first game pays.
  def popular_pool
    @popular_pool ||= POPULAR_PAGES.flat_map { |page| @client.popular_people(page) }
      .select(&:photo_url).map { |p| { id: p.id, name: p.name, photo_url: p.photo_url } }
  end

  def hydrate(person)
    return person if person[:photo_url]

    full = @client.person(person[:id])
    { id: full.id, name: full.name, photo_url: full.photo_url }
  end

  # A photo, enough credits (after the rules), and enough well-known titles among them that a player
  # would recognize the name.
  def presentable?(person, notable = @min_notable)
    return false if person[:photo_url].blank?

    credits = filtered_credits(person[:id])
    credits.size >= @min_credits && credits.count { |c| well_known?(c) } >= notable
  end

  def well_known?(credit) = credit.vote_count.to_i >= WELL_KNOWN_VOTES

  # --- one hop ---

  # From the person at the end of the walk: a well-known title, then a top-billed co-star in it who
  # isn't already in the walk and really does share a credit with them under the rules.
  def hop(walk)
    current = walk.last[:person]
    seen = walk.map { |s| s[:person][:id] }
    titles_for(current[:id]).first(TITLES_PER_HOP).each do |credit|
      candidates(credit, seen).first(CANDIDATES_PER_TITLE).each do |member|
        next unless connected?(current[:id], member[:id])
        next unless presentable?(member)

        return { person: member, title: credit.year ? "#{credit.title} (#{credit.year})" : credit.title }
      end
    end
    nil
  end

  def titles_for(person_id)
    filtered_credits(person_id).select { |c| well_known?(c) }.reject { |c| (Array(c.genre_ids) & BORING_GENRES).any? }
      .sort_by { |c| -c.vote_count.to_i }.first(TOP_TITLES).shuffle(random: @random)
  end

  def candidates(credit, seen)
    cast(credit).first(TOP_BILLED).select { |m| m.photo_url && !seen.include?(m.person_id) }.shuffle(random: @random)
      .map { |m| { id: m.person_id, name: m.name, photo_url: m.photo_url } }
  end

  def cast(credit)
    credit.media_type == "tv" ? @client.tv_aggregate_credits(credit.id) : @client.movie_cast(credit.id)
  end

  # --- rules ---

  def filtered_credits(person_id) = credit_filter.call(@client.person_credits(person_id))

  def connected?(a, b) = checker.call(a, b, @rules).any?

  def credit_filter
    @credit_filter ||= CreditFilter.new(skip_self: @rules[:skip_self], skip_voice: @rules[:skip_voice],
                                        marvel_ids: marvel_ids, movies_only: @rules[:movies_only], years: @rules[:years])
  end

  def checker = @checker ||= ConnectionCheck.new(client: @client, marvel_ids: marvel_ids)

  def marvel_ids
    return unless @rules[:skip_marvel]

    @marvel_ids ||= MarvelTitles.new(tmdb: @client).keys
  end

  def fallback
    @logger.warn("PairGenerator: falling back to a curated pair")
    a, b = @targets.random_pair(random: @random)
    start, target = [ a, b ].map { |t| hydrate({ id: t.id, name: t.name, photo_url: nil }) }
    Pair.new(start: start, target: target, hops: nil, walk: nil, fallback: true)
  end
end
