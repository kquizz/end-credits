require "rails_helper"

RSpec.describe CreditFilter do
  def credit(character: "Role", media_type: "movie", id: 1, year: 2000, genre_ids: [])
    TmdbClient::Credit.new(media_type: media_type, id: id, title: "T", year: year, character: character, genre_ids: genre_ids)
  end

  def kept?(credit, **opts) = described_class.new(**opts).keep?(credit)

  describe "self credits (on by default)" do
    [ "Self", "self", "Himself", "Herself", "Themselves", "Self - Host", "Self (Archive Footage)", "Self - Guest",
      "Himself / Herself", "Self (uncredited)", "Himself - Musical Guest", "Host", "Guest Host",
      "Darth Vader (archive footage)", "Self, Presenter", "Self [as Bob]" ].each do |character|
      it "drops #{character.inspect}" do
        expect(kept?(credit(character: character))).to be(false)
      end
    end

    [ "Selfridge", "Harry Selfridge", "Himself Smith", "Mr. Himself", "Selfish Giant", "Hostess", "Ghost",
      "Diane Lockhart", "", nil ].each do |character|
      it "keeps #{character.inspect}" do
        expect(kept?(credit(character: character))).to be(true)
      end
    end

    it "drops a blank character on a talk show, but not on a drama" do
      expect(kept?(credit(character: "", media_type: "tv", genre_ids: [ 10767 ]))).to be(false)
      expect(kept?(credit(character: nil, media_type: "tv", genre_ids: [ 10763 ]))).to be(false)
      expect(kept?(credit(character: "", media_type: "tv", genre_ids: [ 18 ]))).to be(true)
    end

    it "can be switched off" do
      expect(kept?(credit(character: "Self"), skip_self: false)).to be(true)
    end
  end

  describe "voice acting (opt in)" do
    it "is kept unless skip_voice" do
      expect(kept?(credit(character: "Woody (voice)"))).to be(true)
    end

    [ "Woody (voice)", "Woody (Voice)", "Shrek (voice, uncredited)", "Narrator (voice cameo)" ].each do |character|
      it "drops #{character.inspect}" do
        expect(kept?(credit(character: character), skip_voice: true)).to be(false)
      end
    end

    it "drops anything in the Animation genre" do
      expect(kept?(credit(character: "Woody", genre_ids: [ 16, 35 ]), skip_voice: true)).to be(false)
    end

    it "keeps live action whose character merely mentions voice" do
      expect(kept?(credit(character: "Voice of Reason"), skip_voice: true)).to be(true)
      expect(kept?(credit(character: "Mr. Voicemail", genre_ids: [ 35 ]), skip_voice: true)).to be(true)
    end
  end

  describe "marvel (opt in, from a precomputed set)" do
    let(:marvel) { Set["movie:299534", "tv:1403"] }

    it "drops titles in the set, matching on media type as well as id" do
      expect(kept?(credit(media_type: "movie", id: 299_534), marvel_ids: marvel)).to be(false)
      expect(kept?(credit(media_type: "tv", id: 1403), marvel_ids: marvel)).to be(false)
      expect(kept?(credit(media_type: "tv", id: 299_534), marvel_ids: marvel)).to be(true)
    end

    it "is off when no set is given" do
      expect(kept?(credit(media_type: "movie", id: 299_534))).to be(true)
    end
  end

  describe "movies only and year range" do
    it "drops TV when movies_only" do
      expect(kept?(credit(media_type: "tv"), movies_only: true)).to be(false)
      expect(kept?(credit(media_type: "movie"), movies_only: true)).to be(true)
    end

    it "keeps only years inside the range, and drops undated credits when a range is set" do
      range = 1990..1999
      expect(kept?(credit(year: 1990), years: range)).to be(true)
      expect(kept?(credit(year: 1999), years: range)).to be(true)
      expect(kept?(credit(year: 2000), years: range)).to be(false)
      expect(kept?(credit(year: nil), years: range)).to be(false)
      expect(kept?(credit(year: nil))).to be(true)
    end
  end

  describe "#call" do
    it "filters a list" do
      list = [ credit(id: 1), credit(id: 2, character: "Self"), credit(id: 3, character: "X (voice)") ]

      expect(described_class.new(skip_voice: true).call(list).map(&:id)).to eq([ 1 ])
    end
  end
end
