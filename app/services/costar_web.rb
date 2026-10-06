# People who appear in at least `min_series` of the chosen TV series, sized by how many
# episodes they matched. Series-level overlap only: it can't say two people shared an episode.
class CostarWeb
  Result = Struct.new(:series, :people, keyword_init: true) do
    def as_json(*) = { series: series, people: people }
  end

  def initialize(tmdb: TmdbClient.new, min_series: 2)
    @tmdb = tmdb
    @min_series = min_series
  end

  def call(series_ids)
    ids = Array(series_ids).map(&:to_i).uniq
    names = ids.to_h { |id| [ id, @tmdb.tv(id)[:name] ] }
    credits = ids.to_h { |id| [ id, @tmdb.tv_aggregate_credits(id) ] }

    Result.new(series: ids.map { |id| { id: id, title: names[id] } }, people: people_from(credits))
  end

  private

  def people_from(credits)
    matches = Hash.new { |h, k| h[k] = [] }
    credits.each do |series_id, cast|
      cast.each { |member| matches[member.person_id] << [ series_id, member ] }
    end

    people = matches.values.select { |m| m.size >= @min_series }.map { |m| person(m) }
    people.sort_by! { |p| [ -p[:total_episodes], p[:name].to_s ] }
    scale(people)
  end

  def person(matched)
    member = matched.first.last
    {
      id: member.person_id, name: member.name, photo_url: member.photo_url,
      total_episodes: matched.sum { |_, m| m.total_episodes },
      shows: matched.map do |series_id, m|
        { series_id: series_id, episodes: m.total_episodes,
          characters: m.roles.filter_map { |r| r[:character].presence }.uniq }
      end
    }
  end

  # sqrt keeps a 156-episode lead from dwarfing a 1-episode cameo; the biggest person is 1.0.
  def scale(people)
    top = people.map { |p| Math.sqrt(p[:total_episodes]) }.max.to_f
    people.each { |p| p[:size] = top.zero? ? 1.0 : Math.sqrt(p[:total_episodes]) / top }
  end
end
