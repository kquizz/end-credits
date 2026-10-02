require "rails_helper"

RSpec.describe WikidataClient do
  subject(:client) { described_class.new }

  def binding_for(imdb, article)
    { imdb: { value: imdb }, article: { value: article } }
  end

  def stub_sparql(bindings, status: 200)
    stub_request(:get, "https://query.wikidata.org/sparql")
      .with(query: hash_including("format" => "json"))
      .to_return(status: status, body: { results: { bindings: bindings } }.to_json)
  end

  it "maps IMDb IDs to Wikipedia article titles" do
    stub_sparql([
      binding_for("nm0000158", "https://en.wikipedia.org/wiki/Tom_Hanks"),
      binding_for("nm0000134", "https://en.wikipedia.org/wiki/Robert_De_Niro")
    ])

    expect(client.wikipedia_titles(%w[nm0000158 nm0000134]))
      .to eq("nm0000158" => "Tom Hanks", "nm0000134" => "Robert De Niro")
  end

  it "decodes percent-encoded titles" do
    stub_sparql([ binding_for("nm0000001", "https://en.wikipedia.org/wiki/Zo%C3%AB_Saldana") ])

    expect(client.wikipedia_titles([ "nm0000001" ])).to eq("nm0000001" => "Zoë Saldana")
  end

  it "queries only well-formed IMDb person IDs" do
    stub = stub_sparql([])

    client.wikipedia_titles([ "nm0000158", nil, "tt0000001", "nm1\"; DROP" ])

    expect(stub.with { |req| req.uri.query.include?("nm0000158") && !req.uri.query.include?("tt0000001") })
      .to have_been_requested
  end

  it "makes no request when there is nothing to look up" do
    expect(client.wikipedia_titles([ nil ])).to eq({})
    expect(a_request(:get, /wikidata/)).not_to have_been_made
  end

  it "degrades to no matches on a server error, without caching the failure" do
    cache = ActiveSupport::Cache::MemoryStore.new
    stub_sparql([], status: 500)
    expect(described_class.new(cache: cache).wikipedia_titles([ "nm0000158" ])).to eq({})

    stub_sparql([ binding_for("nm0000158", "https://en.wikipedia.org/wiki/Tom_Hanks") ])
    expect(described_class.new(cache: cache).wikipedia_titles([ "nm0000158" ])).to eq("nm0000158" => "Tom Hanks")
  end
end
