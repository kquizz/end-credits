require "rails_helper"

RSpec.describe MarvelTitles do
  let(:tmdb) { instance_double(TmdbClient) }

  it "unions company and keyword discover results into typed keys" do
    allow(tmdb).to receive(:discover_ids).with("movie", with_companies: 420).and_return([ 1, 2 ])
    allow(tmdb).to receive(:discover_ids).with("movie", with_keywords: 180_547).and_return([ 2, 3 ])
    allow(tmdb).to receive(:discover_ids).with("tv", with_companies: 420).and_return([ 2 ])
    allow(tmdb).to receive(:discover_ids).with("tv", with_companies: 38_679).and_return([ 9 ])
    allow(tmdb).to receive(:discover_ids).with("tv", with_keywords: 180_547).and_return([])

    expect(described_class.new(tmdb: tmdb).keys).to eq(Set["movie:1", "movie:2", "movie:3", "tv:2", "tv:9"])
  end
end
