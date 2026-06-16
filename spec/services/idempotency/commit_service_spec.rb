require 'rails_helper'

RSpec.describe Idempotency::CommitService do
  let(:redis) { double('redis') }
  let(:id_key) { 'test-key' }
  let(:token) { 'commit-token' }

  it 'returns ok and persists record when redis returns ok' do
    allow(redis).to receive(:eval).and_return(['ok'])
    record_double = instance_double('IdempotencyRecord', save!: true)
    allow(IdempotencyRecord).to receive(:find_or_initialize_by).and_return(record_double)

    svc = described_class.new(id_key: id_key, token: token, payload: { 'status' => 201, 'body' => { 'x' => 1 } }, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:ok)
    expect(IdempotencyRecord).to have_received(:find_or_initialize_by).with(idempotency_key: id_key)
  end

  it 'returns already with stored response when redis returns already' do
    # simulate Lua returning {'already', '200', '{"foo":"bar"}'}
    allow(redis).to receive(:eval).and_return(['already', '200', '{"foo":"bar"}'])
    svc = described_class.new(id_key: id_key, token: token, payload: {}, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:already)
    expect(res[:status_code]).to eq(200)
    expect(res[:body]).to eq({'foo' => 'bar'})
  end

  it 'returns conflict when redis returns conflict' do
    allow(redis).to receive(:eval).and_return(['conflict'])
    svc = described_class.new(id_key: id_key, token: token, payload: {}, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:conflict)
  end

  it 'returns no_key when redis returns no_key' do
    allow(redis).to receive(:eval).and_return(['no_key'])
    svc = described_class.new(id_key: id_key, token: token, payload: {}, redis: redis)
    res = svc.call
    expect(res[:status]).to eq(:no_key)
  end
end
