# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpController, type: :controller do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_mcp_dict', description: 'Test dictionary for MCP') }

  before do
    # Create test entries
    entries_data = [
      ['cancer', '0004992', 'cancer', 'cancer', 6, EntryMode::GRAY, false, dictionary.id],
      ['diabetes', '0005015', 'diabetes', 'diabetes', 8, EntryMode::GRAY, false, dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      entries_data,
      validate: false
    )

    dictionary.entries.update_all(searchable: true)
    dictionary.update_entries_num
  end

  def mock_http_response(status:, body:, content_type: 'application/json')
    response_class = status == 200 ? Net::HTTPSuccess : Net::HTTPBadRequest
    response = response_class.new('1.1', status.to_s, status == 200 ? 'OK' : 'Bad Request')
    allow(response).to receive(:code).and_return(status.to_s)
    body_str = body.is_a?(String) ? body : body.to_json
    allow(response).to receive(:body).and_return(body_str)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == 200)
    response
  end

  describe 'POST #streamable_http' do
    let(:jsonrpc_request) do
      {
        jsonrpc: '2.0',
        id: 1,
        method: method_name,
        params: params
      }
    end

    before do
      request.content_type = 'application/json'
    end

    describe 'tools/call list_dictionaries' do
      let(:method_name) { 'tools/call' }
      let(:params) do
        {
          'name' => 'list_dictionaries',
          'arguments' => {}
        }
      end

      context 'with available dictionaries' do
        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: [
                { 'name' => 'MONDO', 'description' => 'Mondo Disease Ontology', 'maintainer' => 'admin' },
                { 'name' => 'HPO', 'description' => 'Human Phenotype Ontology', 'maintainer' => 'admin' }
              ]
            )
          end
        end

        it 'returns list of dictionaries' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['content']).to be_an(Array)

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('Found 2 dictionaries')
          expect(result_text).to include('MONDO')
          expect(result_text).to include('HPO')
        end
      end

      context 'with no dictionaries' do
        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: [])
          end
        end

        it 'returns empty list message' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('Found 0 dictionaries')
        end
      end
    end

    describe 'tools/call get_dictionary_description' do
      let(:method_name) { 'tools/call' }

      context 'with valid dictionary name' do
        let(:params) do
          {
            'name' => 'get_dictionary_description',
            'arguments' => {
              'name' => 'MONDO'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: 'Mondo Disease Ontology is a semi-automatically constructed ontology.'
            )
          end
        end

        it 'returns dictionary description' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('Description for dictionary "MONDO"')
          expect(result_text).to include('semi-automatically constructed ontology')
        end
      end

      context 'with missing dictionary name' do
        let(:params) do
          {
            'name' => 'get_dictionary_description',
            'arguments' => {}
          }
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Dictionary name is required')
        end
      end

      context 'with unknown dictionary' do
        let(:params) do
          {
            'name' => 'get_dictionary_description',
            'arguments' => {
              'name' => 'nonexistent'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 400,
              body: { 'message' => 'Dictionary not found: nonexistent' }
            )
          end
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Dictionary not found')
        end
      end
    end

    describe 'tools/call find_ids' do
      let(:method_name) { 'tools/call' }

      context 'with single label' do
        let(:params) do
          {
            'name' => 'find_ids',
            'arguments' => {
              'labels' => 'cancer',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: { 'cancer' => ['0004992'] }
            )
          end
        end

        it 'returns identifier for the label' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('cancer')
          expect(result_text).to include('0004992')
        end
      end

      context 'with multiple labels' do
        let(:params) do
          {
            'name' => 'find_ids',
            'arguments' => {
              'labels' => 'cancer,diabetes',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: {
                'cancer' => ['0004992'],
                'diabetes' => ['0005015']
              }
            )
          end
        end

        it 'returns identifiers for all labels' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('cancer')
          expect(result_text).to include('0004992')
          expect(result_text).to include('diabetes')
          expect(result_text).to include('0005015')
        end
      end

      context 'with missing labels parameter' do
        let(:params) do
          {
            'name' => 'find_ids',
            'arguments' => {
              'dictionary' => dictionary.name
            }
          }
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Labels are required')
        end
      end

      context 'with missing dictionary parameter' do
        let(:params) do
          {
            'name' => 'find_ids',
            'arguments' => {
              'labels' => 'cancer'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: { 'cancer' => ['0004992'] }
            )
          end
        end

        it 'searches all public dictionaries' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('all public dictionaries')
        end
      end

      context 'with label not found in dictionary' do
        let(:params) do
          {
            'name' => 'find_ids',
            'arguments' => {
              'labels' => 'nonexistent_term',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: { 'nonexistent_term' => [] }
            )
          end
        end

        it 'returns empty result for the label' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['isError']).to be_falsey
        end
      end
    end

    describe 'tools/call search' do
      let(:method_name) { 'tools/call' }

      context 'with valid search query' do
        let(:params) do
          {
            'name' => 'search',
            'arguments' => {
              'labels' => 'canc',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: { 'canc' => ['0004992'] }
            )
          end
        end

        it 'returns search results' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('0004992')
        end
      end

      context 'with missing labels parameter' do
        let(:params) do
          {
            'name' => 'search',
            'arguments' => {
              'dictionary' => dictionary.name
            }
          }
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Labels are required')
        end
      end

      context 'with missing dictionary parameter' do
        let(:params) do
          {
            'name' => 'search',
            'arguments' => {
              'labels' => 'cancer'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: { 'cancer' => ['0004992'] }
            )
          end
        end

        it 'searches all public dictionaries' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('all public dictionaries')
        end
      end
    end

    describe 'tools/call find_terms' do
      let(:method_name) { 'tools/call' }

      context 'with single identifier' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'ids' => '0004992',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do |http, req|
            # Verify the request uses 'identifiers' parameter, not 'ids'
            expect(req.path).to include('identifiers=')
            expect(req.path).not_to match(/[?&]ids=/)

            mock_http_response(
              status: 200,
              body: { '0004992' => { 'label' => 'cancer', 'dictionary' => dictionary.name } }
            )
          end
        end

        it 'returns the term for the identifier' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['content']).to be_an(Array)
          expect(json_response['result']['content'].first['text']).to include('cancer')
        end

        it 'uses identifiers parameter (not ids) in the internal request' do
          # The expectation is in the before block's allow_any_instance_of
          post :streamable_http, body: jsonrpc_request.to_json
          expect(response).to have_http_status(:success)
        end
      end

      context 'with multiple identifiers' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'ids' => '0004992,0005015',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 200,
              body: {
                '0004992' => { 'label' => 'cancer', 'dictionary' => dictionary.name },
                '0005015' => { 'label' => 'diabetes', 'dictionary' => dictionary.name }
              }
            )
          end
        end

        it 'returns terms for all identifiers' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['content']).to be_an(Array)

          result_text = json_response['result']['content'].first['text']
          expect(result_text).to include('cancer')
          expect(result_text).to include('diabetes')
        end
      end

      context 'with missing ids parameter' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'dictionary' => dictionary.name
            }
          }
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('IDs are required')
        end
      end

      context 'with missing dictionary parameter' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'ids' => '0004992'
            }
          }
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Dictionary name is required')
        end
      end

      context 'with unknown dictionary' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'ids' => '0004992',
              'dictionary' => 'nonexistent_dictionary'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(
              status: 400,
              body: { 'message' => 'unknown dictionary: nonexistent_dictionary.' }
            )
          end
        end

        it 'returns an error' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('unknown dictionary')
        end
      end

      context 'with identifier not found in dictionary' do
        let(:params) do
          {
            'name' => 'find_terms',
            'arguments' => {
              'ids' => '9999999',
              'dictionary' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: {})
          end
        end

        it 'returns empty result' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['isError']).to be_falsey
        end
      end
    end
  end
end
