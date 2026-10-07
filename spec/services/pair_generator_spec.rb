require "rails_helper"

RSpec.describe PairGenerator do
  # A tiny TMDb: person i appears in movie 100+i-1 and 100+i, so movie 100+i has cast [i, i+1]. People
  # 1..6 form a chain; `extra_movies` ({ id => [person ids] }) add shortcuts.
  let(:fake_client_class) do
    Class.new do
      attr_reader :calls

      def initialize(people: 1..6, extra_movies: {}, genres: {}, votes: {}, popular: [ 1 ])
        @people = people.to_a
        @movies = people.to_a.each_cons(2).to_h { |a, b| [ 100 + a, [ a, b ] ] }.merge(extra_movies)
        @genres = genres
        @votes = votes
        @popular = popular
        @calls = Hash.new(0)
      end

      def popular_people(_page = 1)
        @popular.map { |id| person(id) }
      end

      def person(id)
        TmdbClient::PersonResult.new(id: id, name: "Person #{id}", known_for: [], photo_url: "p#{id}.jpg")
      end

      def person_credits(id)
        @calls[:credits] += 1
        @movies.select { |_, cast| cast.include?(id) }.map do |movie_id, _|
          TmdbClient::Credit.new(media_type: "movie", id: movie_id, title: "Movie #{movie_id}", year: 2000, character: "Role",
                                 genre_ids: @genres.fetch([ id, movie_id ], []), popularity: movie_id.to_f, vote_count: @votes.fetch(movie_id, 5000))
        end
      end

      def movie_cast(id)
        @movies.fetch(id).map { |pid| TmdbClient::CastMember.new(person_id: pid, name: "Person #{pid}", photo_url: "p#{pid}.jpg") }
      end

      def tv_aggregate_credits(_id) = []
    end
  end

  let(:targets) { instance_double(TargetList, all: [], random_pair: [ TargetList::Person.new(id: 31, name: "Tom Hanks"), TargetList::Person.new(id: 5064, name: "Meryl Streep") ]) }
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }

  def generator(client, **opts)
    described_class.new(client: client, targets: targets, random: Random.new(1), min_credits: 1, min_notable: 1, target_notable: 1, logger: logger, **opts)
  end

  it "walks k hops from a popular start and returns the last person as the target" do
    pair = generator(fake_client_class.new, hops: 3..3).call

    expect(pair).to have_attributes(fallback: false, hops: 3)
    expect(pair.start).to include(id: 1, name: "Person 1")
    expect(pair.target[:id]).to eq(4)
    expect(pair.walk.map { |s| s[:person][:id] }).to eq([ 1, 2, 3, 4 ])
    expect(pair.walk.drop(1).map { |s| s[:title] }).to eq([ "Movie 101 (2000)", "Movie 102 (2000)", "Movie 103 (2000)" ])
    expect(pair.describe).to include("Person 1 -[Movie 101 (2000)]-> Person 2")
  end

  it "only produces pairs reachable within k hops under the rules, every step verified" do
    client = fake_client_class.new
    checker = ConnectionCheck.new(client: client)

    20.times do |seed|
      pair = described_class.new(client: client, targets: targets, random: Random.new(seed), min_credits: 1, min_notable: 1, target_notable: 1, logger: logger).call
      expect(pair.fallback).to be(false)
      expect(pair.hops).to be_between(3, 5)
      pair.walk.each_cons(2) do |a, b|
        expect(checker.call(a[:person][:id], b[:person][:id], skip_self: true, skip_voice: true)).not_to be_empty
      end
      expect(pair.walk.map { |s| s[:person][:id] }.uniq.size).to eq(pair.walk.size)
    end
  end

  it "never lets the pair share a credit directly, falling back if it can't avoid it" do
    # 1-2-3 chain plus a movie that puts 1 and 3 together: every 2-hop walk ends next to its start.
    client = fake_client_class.new(people: 1..3, extra_movies: { 200 => [ 1, 3 ] })

    pair = generator(client, hops: 2..2).call

    expect(pair.fallback).to be(true)
    expect(pair.start[:name]).to eq("Person 31")
  end

  it "does not hop through a voice credit when the rule is on, and does when it's off" do
    client = fake_client_class.new(people: 1..4, genres: { [ 2, 102 ] => [ 16 ], [ 3, 102 ] => [ 16 ] })

    expect(generator(client, hops: 3..3, rules: { skip_voice: true }, attempts: 3).call.fallback).to be(true)
    expect(generator(client, hops: 3..3, rules: { skip_voice: false }, attempts: 3).call.fallback).to be(false)
  end

  it "rejects people without enough credits to be recognizable" do
    client = fake_client_class.new(people: 1..4)

    expect(described_class.new(client: client, targets: targets, random: Random.new(1), min_credits: 3, min_notable: 1, target_notable: 1,
                               hops: 3..3, attempts: 2, logger: logger).call.fallback).to be(true)
  end

  it "only hops through titles people have heard of" do
    client = fake_client_class.new(people: 1..4, votes: { 103 => 12 })

    expect(generator(client, hops: 3..3, attempts: 3).call.fallback).to be(true)
  end

  it "needs a target with enough well-known titles to be recognizable" do
    client = fake_client_class.new(people: 1..4)

    pair = described_class.new(client: client, targets: targets, random: Random.new(1), min_credits: 1, min_notable: 1,
                               target_notable: 2, hops: 3..3, attempts: 2, logger: logger).call

    expect(pair.fallback).to be(true) # the target, person 4, has a single credit
  end

  it "falls back to a curated pair when TMDb keeps failing, without raising" do
    client = fake_client_class.new
    allow(client).to receive(:popular_people).and_raise(TmdbClient::Error, "boom")
    allow(client).to receive(:person) { |id| TmdbClient::PersonResult.new(id: id, name: "Curated #{id}", photo_url: "x.jpg") }

    pair = generator(client).call

    expect(pair).to have_attributes(fallback: true, hops: nil, walk: nil)
    expect([ pair.start[:id], pair.target[:id] ]).to eq([ 31, 5064 ])
    expect(pair.describe).to include("curated fallback")
  end

  it "draws the start from the curated list too and fetches their photo" do
    client = fake_client_class.new(popular: [])
    allow(targets).to receive(:all).and_return([ TargetList::Person.new(id: 1, name: "Person 1") ])

    expect(generator(client, hops: 3..3).call.start).to include(id: 1, photo_url: "p1.jpg")
  end
end
