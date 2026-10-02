require "rails_helper"

RSpec.describe WikipediaClient do
  subject(:client) { described_class.new }

  describe "#search" do
    it "returns candidate people with title and description" do
      body = {
        pages: [
          { title: "John Legend", description: "American singer and songwriter",
            thumbnail: { url: "//img/jl.jpg" } },
          { title: "Legend (John Legend album)", description: "2022 studio album",
            thumbnail: nil }
        ]
      }.to_json

      stub_request(:get, "https://en.wikipedia.org/w/rest.php/v1/search/page")
        .with(query: hash_including("q" => "john legend"))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      results = client.search("john legend")

      expect(results.map(&:title)).to eq([ "John Legend", "Legend (John Legend album)" ])
      expect(results.first.description).to eq("American singer and songwriter")
    end

    it "returns [] for a blank query without calling the API" do
      expect(client.search("  ")).to eq([])
      expect(a_request(:get, /wikipedia/)).not_to have_been_made
    end
  end

  describe "#profile" do
    it "returns categories, the Wikidata QID, and a thumbnail" do
      body = {
        query: {
          pages: {
            "12345" => {
              title: "John Legend",
              pageprops: { wikibase_item: "Q44857" },
              thumbnail: { source: "https://img/jl.jpg" },
              categories: [
                { title: "Category:Grammy Award winners" },
                { title: "Category:Tony Award winners" }
              ]
            }
          }
        }
      }.to_json

      stub_request(:get, "https://en.wikipedia.org/w/api.php")
        .with(query: hash_including("titles" => "John Legend", "action" => "query"))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      profile = client.profile("John Legend")

      expect(profile.title).to eq("John Legend")
      expect(profile.qid).to eq("Q44857")
      expect(profile.thumbnail_url).to eq("https://img/jl.jpg")
      expect(profile.categories).to include("Category:Grammy Award winners")
    end

    it "handles a page with no pageprops or thumbnail" do
      body = { query: { pages: { "1" => { title: "Nobody", categories: [] } } } }.to_json
      stub_request(:get, "https://en.wikipedia.org/w/api.php")
        .with(query: hash_including("titles" => "Nobody"))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      profile = client.profile("Nobody")
      expect(profile.qid).to be_nil
      expect(profile.thumbnail_url).to be_nil
      expect(profile.categories).to eq([])
    end
  end
  describe "#profiles" do
    def stub_api(body, **query)
      stub_request(:get, "https://en.wikipedia.org/w/api.php")
        .with(query: hash_including(query))
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    it "resolves many titles in one call, keyed by the requested title" do
      stub_api(
        { query: { pages: {
          "1" => { title: "Viola Davis", pageprops: { wikibase_item: "Q1" },
                   categories: [ { title: "Category:Tony Award winners" } ] },
          "2" => { title: "John Legend", categories: [ { title: "Category:Grammy Award winners" } ] }
        } } },
        "titles" => "Viola Davis|John Legend"
      )

      result = client.profiles([ "Viola Davis", "John Legend" ])

      expect(result.keys).to contain_exactly("Viola Davis", "John Legend")
      expect(result["Viola Davis"].categories).to eq([ "Category:Tony Award winners" ])
      expect(a_request(:get, /api.php/)).to have_been_made.once
    end

    it "follows redirects and normalization back to the requested title" do
      stub_api(
        { query: {
          normalized: [ { from: "tom hanks", to: "Tom hanks" } ],
          redirects: [ { from: "Tom hanks", to: "Tom Hanks" } ],
          pages: { "9" => { title: "Tom Hanks", categories: [ { title: "Category:Academy Award winners" } ] } }
        } },
        "titles" => "tom hanks"
      )

      expect(client.profiles([ "tom hanks" ])["tom hanks"].title).to eq("Tom Hanks")
    end

    it "merges categories across continuation pages" do
      stub_api(
        { continue: { clcontinue: "1|Next", continue: "||" },
          query: { pages: { "1" => { title: "Viola Davis", categories: [ { title: "Category:A" } ] } } } },
        "titles" => "Viola Davis"
      )
      stub_api(
        { query: { pages: { "1" => { title: "Viola Davis", categories: [ { title: "Category:B" } ] } } } },
        "titles" => "Viola Davis", "clcontinue" => "1|Next"
      )

      expect(client.profiles([ "Viola Davis" ])["Viola Davis"].categories)
        .to eq([ "Category:A", "Category:B" ])
    end

    it "omits titles that do not exist" do
      stub_api({ query: { pages: { "-1" => { title: "Zzzz", missing: "" } } } }, "titles" => "Zzzz")

      expect(client.profiles([ "Zzzz" ])).to eq({})
    end

    it "makes no request for an empty list" do
      expect(client.profiles([])).to eq({})
      expect(a_request(:get, /wikipedia/)).not_to have_been_made
    end
  end
end
