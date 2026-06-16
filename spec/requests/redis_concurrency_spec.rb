require 'rails_helper'
require 'securerandom'

RSpec.describe 'Redis Lua script concurrency', type: :model do
  it 'only allows one first claimant under concurrent evals' do
    script = File.read(Rails.root.join('lib/redis_scripts/check_and_claim.lua'))
    key = "idem:spec-#{SecureRandom.hex(6)}"
    results = []

    threads = 10.times.map do
      Thread.new do
        token = SecureRandom.uuid
        r = Redis.current.eval(script, keys: [key], argv: ['fp', token, 86400])
        results << r
      end
    end

    threads.each(&:join)

    tokens = results.map { |r| r[2] || r[1] }.compact.uniq
    expect(tokens.size).to eq(1)

    first_count = results.count { |r| r[0] == 'first' }
    expect(first_count).to eq(1)
  end
end
