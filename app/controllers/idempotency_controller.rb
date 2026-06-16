# frozen_string_literal: true

class IdempotencyController < ApplicationController
  def check
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    return render json: { error: 'missing idempotency key' }, status: :bad_request unless id_key.present?

    body = request.raw_post.to_s
    res = Idempotency::CheckService.new(id_key: id_key, body: body).call

    case res[:status]
    when :first then render json: { token: res[:token] }, status: :ok
    when :inflight then render json: { token: res[:token], status: 'inflight' }, status: :ok
    when :committed then render json: res[:body], status: res[:status_code]
    when :conflict then head :conflict
    else head :internal_server_error
    end
  end

  def commit
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    token = request.headers['Idempotency-Commit-Token'] || request.headers['HTTP_IDEMPOTENCY_COMMIT_TOKEN']
    return render json: { error: 'missing headers' }, status: :bad_request unless id_key.present? && token.present?

    payload = parse_json_request_body

    res = Idempotency::CommitService.new(id_key: id_key, token: token, payload: payload).call

    case res[:status]
    when :ok then render json: { ok: true }, status: :ok
    when :already then render json: res[:body], status: res[:status_code]
    when :conflict then head :conflict
    when :no_key then head :not_found
    else head :internal_server_error
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

  def parse_json_request_body
    JSON.parse(request.body.read)
  rescue JSON::ParserError, EOFError
    {}
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
