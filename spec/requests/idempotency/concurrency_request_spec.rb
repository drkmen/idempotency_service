require 'net/http'
require 'uri'
require 'securerandom'

RSpec.describe 'Idempotency concurrency', type: :request do
  subject(:results) do
    threads = []
    responses = Queue.new

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
        rescue StandardError => e
          responses << { error: e.message }
        end
      end
    end

    threads.each(&:join)

    arr = []
    arr << responses.pop while !responses.empty?
    arr
  end

  let(:uri) { URI('http://localhost:3000/idempotency/check') }
  let(:id_key) { "spec-#{SecureRandom.hex(8)}" }
  let(:body) { { amount: 1 }.to_json }
  let(:headers) { { 'Content-Type' => 'application/json', 'Idempotency-Key' => id_key } }
  let(:concurrency) { 10 }

  it 'allows exactly one first claimant under concurrent HTTP /idempotency/check requests' do
    expect(results.size).to eq(concurrency)

    tokens = results.map { |r| r[:body].is_a?(Hash) ? r[:body]['token'] : nil }.compact.uniq
    expect(tokens.size).to eq(1)

    first_count = results.count { |r| r[:body].is_a?(Hash) && !r[:body].key?('status') }
    inflight_count = results.count { |r| r[:body].is_a?(Hash) && r[:body]['status'] == 'inflight' }

    aggregate_failures do
      expect(first_count).to eq(1)
      expect(inflight_count).to eq(concurrency - 1)
    end
  end
end
