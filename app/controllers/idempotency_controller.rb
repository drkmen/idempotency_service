require 'securerandom'
require 'digest'

class IdempotencyController < ApplicationController
  def check
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    return render json: {error: 'missing idempotency key'}, status: 400 unless id_key.present?
    body = request.raw_post.to_s

    service = Idempotency::CheckService.new(id_key: id_key, body: body)
    res = service.call

    case res[:status]
    when :first
      render json: {token: res[:token]}, status: 200
    when :inflight
      render json: {token: res[:token], status: 'inflight'}, status: 200
    when :committed
      render json: res[:body], status: res[:status_code]
    when :conflict
      head :conflict
    else
      head :internal_server_error
    end
  end

  def commit
    id_key = request.headers['Idempotency-Key'] || request.headers['HTTP_IDEMPOTENCY_KEY']
    token = request.headers['Idempotency-Commit-Token'] || request.headers['HTTP_IDEMPOTENCY_COMMIT_TOKEN']
    return render json: {error: 'missing headers'}, status: 400 unless id_key.present? && token.present?

    begin
      payload = JSON.parse(request.body.read)
    rescue JSON::ParserError, EOFError
      payload = {}
    end

    service = Idempotency::CommitService.new(id_key: id_key, token: token, payload: payload)
    res = service.call

    case res[:status]
    when :ok
      render json: {ok: true}, status: 200
    when :already
      render json: res[:body], status: res[:status_code]
    when :conflict
      head :conflict
    when :no_key
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
