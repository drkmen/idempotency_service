require 'json'
require 'time'

module Idempotency
  class CommitService
    attr_reader :id_key, :token, :payload, :redis_key, :redis, :ttl

    def initialize(id_key:, token:, payload: {}, redis: $redis, ttl: ENV['IDEMPOTENCY_TTL_SECONDS'])
      @id_key = id_key
      @token = token
      @payload = payload || {}
      @ttl = (ttl || 86400).to_i
      @redis_key = "idem:#{id_key}"
      @redis = redis
    end

    def call
      status_code = (payload['status'] || 200).to_i
      body = payload['body'] || {}
      script = File.read(Rails.root.join('lib/redis_scripts/commit_and_store.lua'))
      res = redis.eval(script, keys: [redis_key], argv: [token, status_code, body.to_json, ttl])

      case res[0]
      when 'ok'
        persist_record(status_code, body)
        { status: :ok }
      when 'already'
        # commit_and_store.lua returns {'already', response_status, response_body}
        stored_status = res[2] ? res[2].to_i : status_code
        stored_body = res[3] || res[2]
        parsed = parse_json(res[3] || res[2])
        { status: :already, status_code: stored_status, body: parsed }
      when 'conflict'
        { status: :conflict }
      when 'no_key'
        { status: :no_key }
      else
        { status: :error }
      end
    end

    private

    def persist_record(status_code, body)
      begin
        record = IdempotencyRecord.find_or_initialize_by(idempotency_key: id_key)
        record.fingerprint = redis.hget(redis_key, 'fingerprint')
        record.response_body = body
        record.response_status = status_code
        record.expires_at = Time.now + ttl
        record.save!
      rescue => e
        Rails.logger.error("Failed to persist idempotency record: #{e.message}")
      end
    end

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
