class Tool
  Entry = Struct.new(:slug, :title, :blurb, :emoji, :path, keyword_init: true) do
    def live? = path.present?
  end

  # Add a path once a tool ships; until then it renders as "coming soon".
  ALL = [
    Entry.new(slug: "egot", title: "EGOT Tracker", emoji: "🏆",
              blurb: "How close is someone to an Emmy, Grammy, Oscar and Tony?"),
    Entry.new(slug: "cast", title: "Cast & EGOTs", emoji: "🎬",
              blurb: "Pick a movie or episode and see every cast member's EGOT progress.",
              path: "/cast"),
    Entry.new(slug: "costars", title: "Co-star Web", emoji: "🕸️",
              blurb: "Who in this cast worked together on something else?"),
    Entry.new(slug: "degrees", title: "Six Degrees", emoji: "🔗",
              blurb: "Connect two actors through shared credits. No Marvel, no voice acting.")
  ].freeze

  def self.all = ALL
end
