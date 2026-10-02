# Ages of a cast on a given date (a movie's release or an episode's air date), from TMDb birthdays.
class AgeLookup
  Row = Struct.new(:member, :on, :birthday, :deathday, :age, keyword_init: true) do
    def unknown? = age.unknown?
    # Died before the premiere: an "age" would be nonsense, so callers show a dagger instead.
    def posthumous? = !deathday.nil? && !on.nil? && deathday < on
    def known_age? = !unknown? && !posthumous?
  end

  def initialize(tmdb: TmdbClient.new)
    @tmdb = tmdb
  end

  def call(cast, on:)
    details = @tmdb.people_details(cast.map(&:person_id))

    cast.map do |member|
      detail = details[member.person_id]
      age = AgeCalculator.age_on(born: detail&.birthday, on: on, died: detail&.deathday)
      age = AgeCalculator::Result.new(years: nil) if age.years&.negative? # bad data: born after the premiere
      Row.new(member: member, on: on, birthday: detail&.birthday, deathday: detail&.deathday, age: age)
    end
  end
end
