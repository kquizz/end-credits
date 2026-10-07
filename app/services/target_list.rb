# The curated Six Degrees people (config/degrees_targets.yml): name + TMDb person id in three tiers.
class TargetList
  TIERS = %w[easy medium hard].freeze
  Person = Struct.new(:id, :name, :tier, keyword_init: true)

  def initialize(path: Rails.root.join("config/degrees_targets.yml"))
    @path = path
  end

  def tiers = TIERS

  def all
    @all ||= YAML.safe_load_file(@path).flat_map do |tier, people|
      Array(people).map { |p| Person.new(id: p["id"], name: p["name"], tier: tier) }
    end
  end

  def find(id) = all.find { |p| p.id == id.to_i }

  # Two different people, both from the tier. No (or an unknown) tier draws from everyone.
  def random_pair(tier: nil, random: Random)
    pool = all.select { |p| p.tier == tier.to_s }
    pool = all if pool.size < 2
    pool.sample(2, random: random)
  end
end
