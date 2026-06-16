# frozen_string_literal: true
require 'json'
require 'securerandom'
require 'digest'

module Idempotency
  # Service performing an idempotency check using Redis lua scripts.
  #
  # It claims the idempotency key (first), returns in-flight token (inflight),
  # or the previously committed response (committed). On fingerprint mismatch
  # it returns conflict.
  class CheckService
    attr_reader :id_key, :body, :fingerprint, :token, :ttl, :redis_key, :redis

    def initialize(id_key:, body:, redis: $redis, ttl: nil)
      @id_key = id_key
      @body = body.to_s
      @fingerprint = Digest::SHA256.hexdigest(@body)
      @token = SecureRandom.uuid
      @ttl = (ttl || ENV['IDEMPOTENCY_TTL_SECONDS'] || 86_400).to_i
      @redis_key = "idem:#{id_key}"
      @redis = redis
    end

    # Execute the claim/read Lua script and normalize the response.
    # Returns a hash with keys :status and additional fields depending on outcome.
    def call
      script = Rails.root.join('lib/redis_scripts/check_and_claim.lua').read
      res = redis.eval(script, keys: [redis_key], argv: [fingerprint, token, ttl])

      case res[0]
      when 'first'   then { status: :first, token: res[1] }
      when 'inflight' then { status: :inflight, token: res[1] }
      when 'committed' then { status: :committed, status_code: res[1].to_i, body: parse_json(res[2]) }
      when 'conflict' then { status: :conflict }
      else { status: :error }
      end
    end

    private

    # Attempt to parse JSON, otherwise return raw string.
    def parse_json(raw)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
