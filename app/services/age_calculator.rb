class AgeCalculator
  Result = Struct.new(:years, :death_year, keyword_init: true) do
    def unknown? = years.nil?
    def deceased? = !death_year.nil?
  end

  def self.age_on(born:, on:, died: nil)
    return Result.new(years: nil) if born.nil? || on.nil?

    years = on.year - born.year
    years -= 1 if ([ on.month, on.day ] <=> [ born.month, born.day ]).negative?
    Result.new(years: years, death_year: died&.year)
  end
end
