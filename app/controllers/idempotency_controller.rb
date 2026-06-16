require 'securerandom'
require 'digest'

class IdempotencyController < ApplicationController

  CHECK_SCRIPT = <<~LUA
    local key = KEYS[1]
    local fp = ARGV[1]
    local token = ARGV[2]
    local ttl = tonumber(ARGV[3])
    if redis.call('exists', key) == 0 then
      redis.call('hmset', key, 'fingerprint', fp, 'token', token, 'committed', '0')
      redis.call('expire', key, ttl)
      return {'first', token}
    else
      local stored_fp = redis.call('hget', key, 'fingerprint')
      if stored_fp == fp then
        local committed = redis.call('hget', key, 'committed')
        if committed == '1' then
          return {'committed', redis.call('hget', key, 'response_status'), redis.call('hget', key, 'response_body')}
        else
          return {'inflight', redis.call('hget', key, 'token')}
        end
      else
        return {'conflict'}
      end
    end
  LUA

  def check
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    return render json: {error: 'missing idempotency key'}, status: 400 unless id_key.present?
    body = request.raw_post.to_s
    fingerprint = Digest::SHA256.hexdigest(body)
    token = SecureRandom.uuid
    ttl = (ENV['IDEMPOTENCY_TTL_SECONDS'] || '86400').to_i
    redis_key = "idem:#{id_key}"
    res = $redis.eval(CHECK_SCRIPT, keys: [redis_key], argv: [fingerprint, token, ttl])

    case res[0]
    when 'first'
      render json: {token: res[1]}, status: 200
    when 'inflight'
      render json: {token: res[1], status: 'inflight'}, status: 200
    when 'committed'
      status = res[1].to_i
      raw_body = res[2]
      parsed = nil
      begin
        parsed = JSON.parse(raw_body)
      rescue
        parsed = raw_body
      end
      render json: parsed, status: status
    when 'conflict'
      head :conflict
    else
      head :internal_server_error
    end
  end

  def commit
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    token = request.headers['Idempotency-Commit-Token'] || request.headers['HTTP_IDEMPOTENCY_COMMIT_TOKEN']
    return render json: {error: 'missing headers'}, status: 400 unless id_key.present? && token.present?
    redis_key = "idem:#{id_key}"

    # Parse JSON payload
    begin
      payload = JSON.parse(request.body.read)
    rescue JSON::ParserError, EOFError
      payload = {}
    end

    status_code = (payload['status'] || 200).to_i
    resp_body = payload['body'] || {}
    ttl = (payload['ttl'] || ENV['IDEMPOTENCY_TTL_SECONDS'] || 86400).to_i

    # Use Lua script to atomically verify token and mark as committed
    script = File.read(Rails.root.join('lib/redis_scripts/commit_and_store.lua'))
    res = $redis.eval(script, keys: [redis_key], argv: [token, status_code, resp_body.to_json, ttl])

    case res[0]
    when 'ok'
      # Persist durable record (best-effort; if this fails, the Redis state will still indicate committed)
      begin
        record = IdempotencyRecord.find_or_initialize_by(idempotency_key: id_key)
        record.fingerprint = $redis.hget(redis_key, 'fingerprint')
        record.response_body = resp_body
        record.response_status = status_code
        record.expires_at = Time.now + ttl
        record.save!
      rescue => e
        Rails.logger.error("Failed to persist idempotency record: #{e.message}")
      end
      render json: {ok: true}, status: 200
    when 'already'
      # Already committed; return stored response
      stored_status = res[1] ? res[1].to_i : 200
      stored_body = res[2]
      begin
        parsed = JSON.parse(stored_body)
      rescue
        parsed = stored_body
      end
      render json: parsed, status: stored_status
    when 'conflict'
      head :conflict
    when 'no_key'
      head :not_found
    else
      head :internal_server_error
    end
  end

  def health
    head :ok
  end

  def ready
    ok = true
    begin
      rc = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
      rc.ping
    rescue => _e
      ok = false
    end
    begin
      ActiveRecord::Base.connection_pool.with_connection { |c| c.active? }
    rescue => _e
      ok = false
    end
    if ok
      head :ok
    else
      head :service_unavailable
    end
  end
end
