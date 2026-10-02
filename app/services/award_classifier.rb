class AwardClassifier
  # [key, label, award phrase] — order defines the 2x2 grid (Emmy, Grammy, Oscar, Tony)
  FAMILIES = [
    [ :emmy,   "Emmy",   "Emmy Award" ],
    [ :grammy, "Grammy", "Grammy Award" ],
    [ :oscar,  "Oscar",  "Academy Award" ],
    [ :tony,   "Tony",   "Tony Award" ]
  ].freeze

  WIN_TOKEN = /winn/i

  def self.call(category_titles)
    names = Array(category_titles).map { |c| c.to_s.delete_prefix("Category:") }
    families = FAMILIES.to_h do |key, _label, phrase|
      wins = names.select { |name| name.include?(phrase) && name.match?(WIN_TOKEN) }
      [ key, { won: wins.any?, wins: wins } ]
    end
    EgotStatus.new(families)
  end
end
