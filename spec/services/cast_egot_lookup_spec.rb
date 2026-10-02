require "rails_helper"

RSpec.describe CastEgotLookup do
  let(:cast) do
    [
      TmdbClient::CastMember.new(person_id: 1, name: "Viola Davis", character: "Lead"),
      TmdbClient::CastMember.new(person_id: 2, name: "Some Extra", character: "Waiter"),
      TmdbClient::CastMember.new(person_id: 3, name: "No Imdb", character: "Cameo")
    ]
  end
  let(:tmdb) { instance_double(TmdbClient, person_imdb_ids: { 1 => "nm1", 2 => "nm2", 3 => nil }) }
  let(:wikidata) { instance_double(WikidataClient, wikipedia_titles: { "nm1" => "Viola Davis" }) }
  let(:wikipedia) do
    instance_double(WikipediaClient, profiles: {
      "Viola Davis" => WikipediaClient::Profile.new(
        title: "Viola Davis",
        categories: [ "Category:Emmy Award winners", "Category:Grammy Award winners",
                      "Category:Academy Award winners", "Category:Tony Award winners" ]
      )
    })
  end

  subject(:rows) { described_class.new(tmdb: tmdb, wikidata: wikidata, wikipedia: wikipedia).call(cast) }

  it "classifies a matched person from their Wikipedia categories" do
    row = rows.first

    expect(row.matched?).to be(true)
    expect(row.wikipedia_title).to eq("Viola Davis")
    expect(row.status).to be_egot
  end

  it "leaves people it cannot tie to an article unknown rather than empty-handed" do
    expect(rows[1..]).to all(have_attributes(status: nil, matched?: false, wikipedia_title: nil))
  end

  it "keeps rows in cast order" do
    expect(rows.map { |r| r.member.name }).to eq([ "Viola Davis", "Some Extra", "No Imdb" ])
  end

  it "only asks Wikipedia about resolved titles" do
    rows

    expect(wikipedia).to have_received(:profiles).with([ "Viola Davis" ])
  end
end
