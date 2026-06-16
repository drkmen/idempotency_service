# frozen_string_literal: true

class IdempotencyController < ApplicationController
  MAX_KEY_LENGTH = 255
  CONTROL_CHAR_REGEX = /\p{Cntrl}/u

  def check
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    return render_api_error('missing_idempotency_key', 'Idempotency-Key header is required', :bad_request) unless id_key.present?

    unless valid_idempotency_key?(id_key)
      return render_api_error('invalid_idempotency_key', 'Idempotency-Key is invalid', :bad_request)
    end

    body = request.raw_post.to_s

    begin
      res = Idempotency::CheckService.new(id_key: id_key, body: body).call
    rescue => e
      return render_api_error('internal_error', 'Internal server error', :service_unavailable)
    end

    case res[:status]
    when :first
      render json: { token: res[:token] }, status: :ok
    when :inflight
      render json: { token: res[:token], status: 'inflight' }, status: :ok
    when :committed
      render json: res[:body], status: res[:status_code]
    when :conflict
      head :conflict
    when :error
      render_api_error(res[:error_code] || 'idempotency_store_unavailable', res[:error_message] || 'Idempotency store unavailable', :service_unavailable)
    else
      render_api_error('internal_error', 'Internal server error', :internal_server_error)
    end
  end

  def commit
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    token = request.headers['Idempotency-Commit-Token'] || request.headers['HTTP_IDEMPOTENCY_COMMIT_TOKEN']

    return render_api_error('missing_idempotency_key', 'Idempotency-Key header is required', :bad_request) unless id_key.present?
    return render_api_error('missing_commit_token', 'Idempotency-Commit-Token header is required', :bad_request) unless token.present?

    unless valid_idempotency_key?(id_key)
      return render_api_error('invalid_idempotency_key', 'Idempotency-Key is invalid', :bad_request)
    end

    unless valid_commit_token?(token)
      return render_api_error('invalid_commit_token', 'Idempotency-Commit-Token is invalid', :bad_request)
    end

    raw = request.body.read.to_s

    if raw.strip.empty?
      payload = {}
    else
      begin
        parsed = JSON.parse(raw)
      rescue JSON::ParserError
        return render_api_error('invalid_json', 'Request body contains malformed JSON', :bad_request)
      end

      unless parsed.is_a?(Hash)
        return render_api_error('invalid_json_type', 'Top-level JSON must be an object', :unprocessable_entity)
      end

      payload = parsed
    end

    if payload.key?('status')
      unless payload['status'].is_a?(Integer) && payload['status'].between?(100, 599)
        return render_api_error('invalid_response_status', 'Response status must be an integer between 100 and 599', :unprocessable_entity)
      end
    end

    payload['body'] = {} unless payload.key?('body')

    begin
      res = Idempotency::CommitService.new(id_key: id_key, token: token, payload: payload).call
    rescue => e
      return render_api_error('internal_error', 'Internal server error', :service_unavailable)
    end

    case res[:status]
    when :ok
      render json: { ok: true }, status: :ok
    when :already
      render json: res[:body], status: res[:status_code]
    when :conflict
      head :conflict
    when :no_key
      head :not_found
    when :error
      render_api_error(res[:error_code] || 'idempotency_store_unavailable', res[:error_message] || 'Idempotency store unavailable', :service_unavailable)
    else
      render_api_error('internal_error', 'Internal server error', :internal_server_error)
    end
  end

  def health
    head :ok
  end

  def ready
    healthy_redis = safe_redis_ping
    healthy_db = safe_db_check
    healthy_redis && healthy_db ? head(:ok) : head(:service_unavailable)
  end

  private

  def render_api_error(code, message, status_sym)
    status = Rack::Utils::SYMBOL_TO_STATUS_CODE[status_sym] || 500
    render json: { error: { code: code, message: message } }, status: status
  end

  def valid_idempotency_key?(k)
    return false if k.nil?
    return false if k.strip.empty?
    return false if k.length > MAX_KEY_LENGTH
    return false if k.match?(CONTROL_CHAR_REGEX)

    true
  end

  def valid_commit_token?(t)
    return false if t.nil?
    return false if t.strip.empty?
    return false if t.length > MAX_KEY_LENGTH
    return false if t.match?(CONTROL_CHAR_REGEX)

    true
  end

  def safe_redis_ping
    Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0')).ping == 'PONG'
  rescue StandardError
    false
  end

  def safe_db_check
    ActiveRecord::Base.connection_pool.with_connection { |c| c.active? }
  rescue StandardError
    false
  end
end
