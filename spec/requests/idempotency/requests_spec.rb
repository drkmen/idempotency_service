require 'rails_helper'

RSpec.describe 'Idempotency endpoints', type: :request do
  describe 'POST /idempotency/check' do
    subject(:do_request) { post path, headers: headers, params: params }

    let(:path) { '/idempotency/check' }
    let(:headers) { { 'Idempotency-Key' => 'key-1' } }
    let(:params) { { foo: 'bar' }.to_json }

    context 'when first claimant' do
      before do
        svc = instance_double(Idempotency::CheckService, call: { status: :first, token: 'tok-1' })
        allow(Idempotency::CheckService).to receive(:new).and_return(svc)
      end

      it 'returns token' do
        do_request
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('token' => 'tok-1')
      end
    end

    context 'when inflight' do
      before do
        svc = instance_double(Idempotency::CheckService, call: { status: :inflight, token: 'tok-2' })
        allow(Idempotency::CheckService).to receive(:new).and_return(svc)
      end

      it 'returns inflight token and status' do
        do_request
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('token' => 'tok-2', 'status' => 'inflight')
      end
    end

    context 'when committed' do
      let(:params) { { x: 'y' }.to_json }

      before do
        svc = instance_double(Idempotency::CheckService, call: { status: :committed, status_code: 201, body: { 'ok' => true } })
        allow(Idempotency::CheckService).to receive(:new).and_return(svc)
      end

      it 'returns stored response and status' do
        do_request
        expect(response).to have_http_status(201)
        expect(JSON.parse(response.body)).to eq({ 'ok' => true })
      end
    end

    context 'when conflict' do
      before do
        svc = instance_double(Idempotency::CheckService, call: { status: :conflict })
        allow(Idempotency::CheckService).to receive(:new).and_return(svc)
      end

      it 'returns 409' do
        do_request
        expect(response).to have_http_status(:conflict)
      end
    end

    context 'when missing idempotency key header' do
      let(:headers) { {} }

      it 'returns 400 with error message' do
        do_request
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to match(/missing idempotency key/)
      end
    end

    context 'when service returns unknown status' do
      before do
        svc = instance_double(Idempotency::CheckService, call: { status: :unknown })
        allow(Idempotency::CheckService).to receive(:new).and_return(svc)
      end

      it 'returns 500' do
        do_request
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'POST /idempotency/commit' do
    subject(:do_request) { post path, headers: headers, params: params }

    let(:path) { '/idempotency/commit' }
    let(:headers) { { 'Idempotency-Key' => 'key-1', 'Idempotency-Commit-Token' => 'tok-commit' } }
    let(:params) { { status: 200, body: { result: 'ok' } }.to_json }

    context 'when commit successful' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :ok })
        expect(Idempotency::CommitService).to receive(:new).with(hash_including(id_key: 'key-1', token: 'tok-commit')).and_return(svc)
      end

      it 'returns ok JSON' do
        do_request
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq({ 'ok' => true })
      end
    end

    context 'when already committed' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :already, status_code: 201, body: { 'msg' => 'done' } })
        allow(Idempotency::CommitService).to receive(:new).and_return(svc)
      end

      it 'returns stored response' do
        do_request
        expect(response).to have_http_status(201)
        expect(JSON.parse(response.body)).to eq({ 'msg' => 'done' })
      end
    end

    context 'when already committed with invalid stored JSON' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :already, status_code: 200, body: 'not-a-json' })
        allow(Idempotency::CommitService).to receive(:new).and_return(svc)
      end

      it 'returns raw body string' do
        do_request
        expect(response).to have_http_status(200)
        expect(response.body).to include('not-a-json')
      end
    end

    context 'when conflict' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :conflict })
        allow(Idempotency::CommitService).to receive(:new).and_return(svc)
      end

      it 'returns 409' do
        do_request
        expect(response).to have_http_status(:conflict)
      end
    end

    context 'when no prior key' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :no_key })
        allow(Idempotency::CommitService).to receive(:new).and_return(svc)
      end

      it 'returns 404' do
        do_request
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when headers missing' do
      let(:headers) { {} }

      it 'returns 400' do
        do_request
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to match(/missing headers/)
      end
    end

    context 'when request body invalid JSON' do
      let(:params) { 'not-json' }

      it 'returns 400 invalid_json' do
        do_request

        expect(response).to have_http_status(:bad_request)
        body = JSON.parse(response.body)
        expect(body).to include('error')
        expect(body['error']['code']).to eq('invalid_json')
      end
    end

    context 'when service returns unknown status' do
      before do
        svc = instance_double(Idempotency::CommitService, call: { status: :something })
        allow(Idempotency::CommitService).to receive(:new).and_return(svc)
      end

      it 'returns 500' do
        do_request
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'GET health and ready' do
    context 'health' do
      it 'returns 200' do
        get '/health'
        expect(response).to have_http_status(:ok)
      end
    end

    context 'ready' do
      it 'returns 200 when services healthy' do
        allow_any_instance_of(Redis).to receive(:ping).and_return('PONG')
        allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_yield(double(active?: true))

        get '/ready'
        expect(response).to have_http_status(:ok)
      end

      it 'returns 503 when redis unhealthy' do
        allow_any_instance_of(Redis).to receive(:ping).and_raise(StandardError)
        allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_yield(double(active?: true))

        get '/ready'
        expect(response).to have_http_status(:service_unavailable)
      end

      it 'returns 503 when db unhealthy' do
        allow_any_instance_of(Redis).to receive(:ping).and_return('PONG')
        allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_raise(StandardError)

        get '/ready'
        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end
end
