require 'net/http'
require 'uri'
require 'securerandom'

RSpec.describe 'Idempotency concurrency', type: :request do
  it 'allows exactly one first claimant under concurrent HTTP /idempotency/check requests' do
    uri = URI('http://localhost:3000/idempotency/check')
    id_key = "spec-#{SecureRandom.hex(8)}"
    body = { amount: 1 }.to_json
    headers = { 'Content-Type' => 'application/json', 'Idempotency-Key' => id_key }

    threads = []
    responses = Queue.new
    concurrency = 10

    concurrency.times do
      threads << Thread.new do
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 5
        req = Net::HTTP::Post.new(uri.request_uri, headers)
        req.body = body
        begin
          res = http.request(req)
          parsed = nil
          begin
            parsed = JSON.parse(res.body) unless res.body.to_s.strip.empty?
          rescue JSON::ParserError
            parsed = res.body
          end
          responses << { code: res.code.to_i, body: parsed }
        rescue => e
          responses << { error: e.message }
        end
      end
    end

    threads.each(&:join)

    results = []
    results << responses.pop while !responses.empty?

    # Ensure all requests succeeded
    expect(results.size).to eq(concurrency)

    tokens = results.map { |r| r[:body].is_a?(Hash) ? r[:body]['token'] : nil }.compact.uniq
    # All tokens should be identical (claim token)
    expect(tokens.size).to eq(1)

    first_count = results.count { |r| r[:body].is_a?(Hash) && !r[:body].key?('status') }
    inflight_count = results.count { |r| r[:body].is_a?(Hash) && r[:body]['status'] == 'inflight' }

    expect(first_count).to eq(1)
    expect(inflight_count).to eq(concurrency - 1)
  end
end
