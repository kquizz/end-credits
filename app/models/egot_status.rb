class EgotStatus
  LABELS = { emmy: "Emmy", grammy: "Grammy", oscar: "Oscar", tony: "Tony" }.freeze

  def initialize(families)
    @families = families
  end

  def won?(key) = @families.fetch(key)[:won]
  def wins(key) = @families.fetch(key)[:wins]
  def score = LABELS.keys.count { |k| won?(k) }
  def egot? = score == 4
  def missing_labels = LABELS.reject { |k, _| won?(k) }.values
end
