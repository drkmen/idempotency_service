require 'rails_helper'

RSpec.describe Idempotency::CheckService, type: :service do
  subject(:call_service) { described_class.new(id_key: id_key, body: body, redis: redis, ttl: ttl).call }

  let(:redis) { instance_double(Redis) }
  let(:id_key) { 'test-key' }
  let(:body) { '{"a":1}' }
  let(:ttl) { 86_400 }

  context 'when redis reports first' do
    before { allow(redis).to receive(:eval).and_return(['first', 'tok-123']) }

    it 'returns first and token' do
      expect(call_service[:status]).to eq(:first)
      expect(call_service[:token]).to eq('tok-123')
    end
  end

  context 'when redis reports inflight' do
    before { allow(redis).to receive(:eval).and_return(['inflight', 'tok-xyz']) }

    it 'returns inflight and token' do
      expect(call_service[:status]).to eq(:inflight)
      expect(call_service[:token]).to eq('tok-xyz')
    end
  end

  context 'when redis reports committed with valid JSON' do
    before { allow(redis).to receive(:eval).and_return(['committed', '200', '{"ok":true}']) }

    it 'returns committed with parsed body and status code' do
      result = call_service
      expect(result[:status]).to eq(:committed)
      expect(result[:status_code]).to eq(200)
      expect(result[:body]).to eq({ 'ok' => true })
    end
  end

  context 'when redis reports committed with invalid JSON' do
    before { allow(redis).to receive(:eval).and_return(['committed', '200', 'not-a-json']) }

    it 'returns committed and raw body string' do
      result = call_service
      expect(result[:status]).to eq(:committed)
      expect(result[:body]).to eq('not-a-json')
    end
  end

  context 'when redis reports conflict' do
    before { allow(redis).to receive(:eval).and_return(['conflict']) }

    it 'returns conflict' do
      expect(call_service[:status]).to eq(:conflict)
    end
  end

  context 'when redis returns unknown status' do
    before { allow(redis).to receive(:eval).and_return(['mystery_status']) }

    it 'returns error' do
      expect(call_service[:status]).to eq(:error)
    end
  end
end
