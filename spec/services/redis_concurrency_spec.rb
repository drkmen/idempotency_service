require 'rails_helper'
require 'securerandom'

RSpec.describe 'Redis Lua script concurrency', type: :model do
  subject(:results) do
    threads = Array.new(concurrency) do
      Thread.new do
        token = SecureRandom.uuid
        $redis.eval(script, keys: [key], argv: ['fp', token, ttl])
      end
    end

    threads.map(&:join)
    results = []
    # The Lua script returns arrays; collect from Redis via separate evals is fine since eval returns synchronously
    # NOTE: threads above return values to main thread via join results; but for simplicity we call eval within threads
    # and push to a shared array under a mutex
    results
  end

  let(:script) { File.read(Rails.root.join('lib/redis_scripts/check_and_claim.lua')) }
  let(:key) { "idem:spec-#{SecureRandom.hex(6)}" }
  let(:concurrency) { 10 }
  let(:ttl) { 86_400 }

  it 'only allows one first claimant under concurrent evals' do
    # Perform threads manually to capture results in a threadsafe way
    results = []
    mutex = Mutex.new

    threads = concurrency.times.map do
      Thread.new do
        token = SecureRandom.uuid
        r = $redis.eval(script, keys: [key], argv: ['fp', token, ttl])
        mutex.synchronize { results << r }
      end
    end

    threads.each(&:join)

    tokens = results.map { |r| r[2] || r[1] }.compact.uniq
    expect(tokens.size).to eq(1)

    first_count = results.count { |r| r[0] == 'first' }
    expect(first_count).to eq(1)
  end
end
