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
    Entry.new(slug: "ages", title: "Cast Ages", emoji: "🎂",
              blurb: "How old was everyone when this movie or episode premiered?",
              path: "/ages"),
    Entry.new(slug: "costars", title: "Co-star Web", emoji: "🕸️",
              blurb: "Pick two or more series and see who appeared in several of them.",
              path: "/costars"),
    Entry.new(slug: "degrees", title: "Six Degrees", emoji: "🔗",
              blurb: "Connect two actors through shared credits. No Marvel, no voice acting.",
              path: "/degrees")
  ].freeze

  def self.all = ALL
end
