require 'rails_helper'

RSpec.describe Idempotency::CheckService do
  let(:redis) { double('redis') }
  let(:id_key) { 'test-key' }
  let(:body) { '{"a":1}' }

  it 'returns first with token when redis reports first' do
    allow(redis).to receive(:eval).and_return(['first', 'tok-123'])
    svc = described_class.new(id_key: id_key, body: body, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:first)
    expect(res[:token]).to eq('tok-123')
  end

  it 'returns inflight when redis reports inflight' do
    allow(redis).to receive(:eval).and_return(['inflight', 'tok-xyz'])
    svc = described_class.new(id_key: id_key, body: body, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:inflight)
    expect(res[:token]).to eq('tok-xyz')
  end

  it 'returns committed with parsed body when redis reports committed' do
    allow(redis).to receive(:eval).and_return(['committed', '200', '{"ok":true}'])
    svc = described_class.new(id_key: id_key, body: body, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:committed)
    expect(res[:status_code]).to eq(200)
    expect(res[:body]).to eq({'ok' => true})
  end

  it 'returns conflict when redis reports conflict' do
    allow(redis).to receive(:eval).and_return(['conflict'])
    svc = described_class.new(id_key: id_key, body: body, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:conflict)
  end
end
