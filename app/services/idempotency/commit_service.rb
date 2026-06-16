# frozen_string_literal: true
require 'json'
require 'time'

module Idempotency
  # Service that commits a response for an idempotency key.
  #
  # Usage:
  #   Idempotency::CommitService.new(id_key: 'k', token: 't', payload: {...}).call
  #
  # Returns a hash with :status and optionally :status_code and :body when already committed.
  class CommitService
    attr_reader :id_key, :token, :payload, :redis_key, :redis, :ttl

    def initialize(id_key:, token:, payload: {}, redis: $redis, ttl: nil)
      @id_key = id_key
      @token = token
      @payload = payload || {}
      @ttl = (ttl || ENV['IDEMPOTENCY_TTL_SECONDS'] || 86_400).to_i
      @redis_key = "idem:#{id_key}"
      @redis = redis
    end

    # Atomically verifies the commit token and stores the response in Redis.
    # Persists a durable record in Postgres (best-effort).
    def call
      status_code = (payload['status'] || 200).to_i
      body = payload['body'] || {}
      script = Rails.root.join('lib/redis_scripts/commit_and_store.lua').read

      begin
        res = redis.eval(script, keys: [redis_key], argv: [token, status_code, body.to_json, ttl])
      rescue StandardError => e
        Rails.logger.error('Idempotency::CommitService - redis unavailable')
        return { status: :error, error_code: 'idempotency_store_unavailable', error_message: 'Idempotency store unavailable' }
      end

      case res[0]
      when 'ok'
        # persist best-effort after a successful redis commit
        persist_record(status_code, body)
        { status: :ok }
      when 'already'
        # commit_and_store.lua returns: ['already', response_status, response_body]
        stored_status = res[1].to_i
        stored_body = res[2]
        { status: :already, status_code: stored_status, body: parse_json(stored_body) }
      when 'conflict'
        { status: :conflict }
      when 'no_key'
        { status: :no_key }
      else
        { status: :error, error_code: 'unknown_redis_response', error_message: 'Unknown response from idempotency store' }
      end
    end

    private

    def persist_record(status_code, body)
      record = IdempotencyRecord.find_or_initialize_by(idempotency_key: id_key)
      record.fingerprint = redis.hget(redis_key, 'fingerprint')
      record.response_body = body
      record.response_status = status_code
      record.expires_at = Time.now + ttl
      record.save!
    rescue => e
      Rails.logger.error("Failed to persist idempotency record: #{e.message}")
      nil
    end

    def parse_json(raw)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
