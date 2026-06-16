require 'rails_helper'

RSpec.describe Idempotency::CommitService, type: :service do
  subject(:call_service) { described_class.new(id_key: id_key, token: token, payload: payload, redis: redis, ttl: ttl).call }

  let(:redis) { instance_double(Redis) }
  let(:id_key) { 'test-key' }
  let(:token) { 'commit-token' }
  let(:ttl) { 3600 }
  let(:payload) { { 'status' => status, 'body' => body } }
  let(:status) { 200 }
  let(:body) { { 'x' => 1 } }

  before { IdempotencyRecord.delete_all }

  context 'when redis returns ok' do
    before do
      allow(redis).to receive(:eval).and_return(['ok'])
      allow(redis).to receive(:hget).with("idem:#{id_key}", 'fingerprint').and_return('fp-commit-1')
    end

    it 'persists an IdempotencyRecord and returns ok' do
      result = call_service

      expect(result[:status]).to eq(:ok)

      record = IdempotencyRecord.find_by(idempotency_key: id_key)
      expect(record).to be_present
      aggregate_failures do
        expect(record.fingerprint).to eq('fp-commit-1')
        expect(record.response_status).to eq(201)
        expect(record.response_body).to eq({ 'x' => 1 })
        expect(record.expires_at).to be_within(5).of(Time.now + ttl)
      end
    end
  end

  context 'when redis returns already' do
    context 'with valid JSON body' do
      before { allow(redis).to receive(:eval).and_return(['already', '200', '{"foo":"bar"}']) }

      it 'returns already and parsed body' do
        result = call_service
        expect(result[:status]).to eq(:already)
        expect(result[:status_code]).to eq(200)
        expect(result[:body]).to eq({ 'foo' => 'bar' })
      end
    end

    context 'with invalid JSON body' do
      before { allow(redis).to receive(:eval).and_return(['already', '200', 'not-a-json']) }

      it 'returns already and raw body string' do
        result = call_service
        expect(result[:status]).to eq(:already)
        expect(result[:body]).to eq('not-a-json')
      end
    end
  end

  context 'when redis returns conflict' do
    before { allow(redis).to receive(:eval).and_return(['conflict']) }

    it 'returns conflict and does not persist' do
      expect(call_service[:status]).to eq(:conflict)
      expect(IdempotencyRecord.find_by(idempotency_key: id_key)).to be_nil
    end
  end

  context 'when redis returns no_key' do
    before { allow(redis).to receive(:eval).and_return(['no_key']) }

    it 'returns no_key and does not persist' do
      expect(call_service[:status]).to eq(:no_key)
      expect(IdempotencyRecord.find_by(idempotency_key: id_key)).to be_nil
    end
  end

  context 'when redis returns unknown response' do
    before { allow(redis).to receive(:eval).and_return(['mystery']) }

    it 'returns error' do
      expect(call_service[:status]).to eq(:error)
    end
  end
end
