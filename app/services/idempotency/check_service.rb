require 'json'
require 'securerandom'
require 'digest'

module Idempotency
  class CheckService
    attr_reader :id_key, :body, :fingerprint, :token, :ttl, :redis_key, :redis

    def initialize(id_key:, body:, redis: $redis, ttl: ENV['IDEMPOTENCY_TTL_SECONDS'])
      @id_key = id_key
      @body = body.to_s
      @fingerprint = Digest::SHA256.hexdigest(@body)
      @token = SecureRandom.uuid
      @ttl = (ttl || 86400).to_i
      @redis_key = "idem:#{id_key}"
      @redis = redis
    end

    def call
      script = File.read(Rails.root.join('lib/redis_scripts/check_and_claim.lua'))
      res = redis.eval(script, keys: [redis_key], argv: [fingerprint, token, ttl])
      case res[0]
      when 'first'
        { status: :first, token: res[1] }
      when 'inflight'
        { status: :inflight, token: res[1] }
      when 'committed'
        status_code = res[1].to_i
        body = parse_json(res[2])
        { status: :committed, status_code: status_code, body: body }
      when 'conflict'
        { status: :conflict }
      else
        { status: :error }
      end
    end

    private

    def parse_json(raw)
      return nil if raw.nil?
      begin
        JSON.parse(raw)
      rescue JSON::ParserError
        raw
      end
    end
  end
end
