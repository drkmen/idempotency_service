require 'securerandom'
require 'digest'

class IdempotencyController < ApplicationController
  skip_before_action :verify_authenticity_token

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
    stored_token = $redis.hget(redis_key, 'token')
    unless stored_token && ActiveSupport::SecurityUtils.secure_compare(stored_token, token)
      return head :conflict
    end

    payload = request.request_parameters rescue {}
    # Expecting JSON like: { "status": 200, "body": {...}, "ttl": 86400 }
    status_code = (payload['status'] || 200).to_i
    resp_body = payload['body'] || {}
    ttl = (payload['ttl'] || ENV['IDEMPOTENCY_TTL_SECONDS'] || 86400).to_i
    expires_at = Time.now + ttl

    record = IdempotencyRecord.find_or_initialize_by(idempotency_key: id_key)
    record.fingerprint = $redis.hget(redis_key, 'fingerprint')
    record.response_body = resp_body
    record.response_status = status_code
    record.expires_at = expires_at
    record.save!

    $redis.hmset(redis_key, 'committed', '1', 'response_status', status_code, 'response_body', resp_body.to_json)
    $redis.expire(redis_key, ttl)

    render json: {ok: true}, status: 200
  end

  def health
    head :ok
  end

  def ready
    ok = true
    begin
      $redis.ping
    rescue => _e
      ok = false
    end
    begin
      ActiveRecord::Base.connection.active?
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
