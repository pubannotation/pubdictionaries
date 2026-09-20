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

        it 'returns list of dictionaries as structured JSON with a link' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']).to be_present
          expect(json_response['result']['content']).to be_an(Array)

          payload = JSON.parse(json_response['result']['content'].first['text'])
          expect(payload.keys).to match_array(%w[dictionaries link])
          expect(payload['dictionaries']).to be_an(Array).and have_attributes(length: 2)
          expect(payload['dictionaries'].map { |d| d['name'] }).to match_array(%w[MONDO HPO])
          # Handler slices these fields when present. Fixture omits entries_num, so
          # only the three that WERE supplied round-trip.
          expect(payload['dictionaries'].first.keys).to match_array(%w[name description maintainer])
          expect(payload['link']).to match(%r{/dictionaries\z})
        end
      end

      context 'with no dictionaries' do
        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: [])
          end
        end

        it 'returns an empty array (no results ≠ error)' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          payload = JSON.parse(JSON.parse(response.body)['result']['content'].first['text'])
          expect(payload['dictionaries']).to eq([])
        end
      end

      context 'with a query argument' do
        # Guards the whole query→URL→response chain: the argument must land in
        # the outgoing request's query string, and the response must include a
        # click-through URL so the user can browse the filtered view.
        let(:params) do
          {
            'name' => 'list_dictionaries',
            'arguments' => { 'query' => 'anatomy' }
          }
        end

        it 'forwards the query as ?query= and surfaces a browsable URL' do
          captured_path = nil
          allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
            captured_path = req.path
            mock_http_response(status: 200, body: [
              { 'name' => 'uberon',  'description' => 'anatomical terms from uberon', 'maintainer' => 'jdkim' },
              { 'name' => 'BTO',     'description' => 'brenda tissue ontology',       'maintainer' => 'admin' }
            ])
          end

          post :streamable_http, body: jsonrpc_request.to_json

          # Wire-level: forwarded via ?query= (URL-encoded)
          expect(captured_path).to eq('/dictionaries.json?query=anatomy')

          # Response-level: JSON payload with both dictionaries listed + the
          # click-through link carrying the same query.
          expect(response).to have_http_status(:success)
          payload = JSON.parse(JSON.parse(response.body)['result']['content'].first['text'])
          expect(payload['dictionaries'].map { |d| d['name'] }).to match_array(%w[uberon BTO])
          expect(payload['link']).to end_with('/dictionaries?query=anatomy')
        end

        it 'URL-encodes multi-word / special-character queries' do
          captured_path = nil
          allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
            captured_path = req.path
            mock_http_response(status: 200, body: [])
          end

          request_with_special_query = {
            jsonrpc: '2.0', id: 1, method: 'tools/call',
            params: { 'name' => 'list_dictionaries', 'arguments' => { 'query' => 'mouse anatomy' } }
          }
          post :streamable_http, body: request_with_special_query.to_json

          # Space → %20 (ERB::Util.url_encode), NOT `+`. Same encoding on
          # the browse URL in the response payload.
          expect(captured_path).to eq('/dictionaries.json?query=mouse%20anatomy')
          payload = JSON.parse(JSON.parse(response.body)['result']['content'].first['text'])
          expect(payload['link']).to end_with('/dictionaries?query=mouse%20anatomy')
        end
      end

      context 'without a query argument (backward compatibility)' do
        # If no query is passed, must hit the unfiltered path (existing
        # consumers must keep working).
        let(:params) do
          { 'name' => 'list_dictionaries', 'arguments' => {} }
        end

        it 'hits /dictionaries.json without a query string' do
          captured_path = nil
          allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
            captured_path = req.path
            mock_http_response(status: 200, body: [])
          end

          post :streamable_http, body: jsonrpc_request.to_json

          expect(captured_path).to eq('/dictionaries.json')
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

        it 'returns the description + link as JSON' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          payload = JSON.parse(JSON.parse(response.body)['result']['content'].first['text'])
          expect(payload.keys).to match_array(%w[description link])
          expect(payload['description']).to include('semi-automatically constructed ontology')
          expect(payload['link']).to end_with('/dictionaries/MONDO')
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

        it 'searches all public dictionaries (link is the un-scoped /find_ids)' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          payload = JSON.parse(json_response['result']['content'].first['text'])
          # No dictionary → link points at the global /find_ids form, not
          # /dictionaries/{dict}/find_ids.
          expect(payload['link']).to match(%r{/find_ids\?label=cancer\z})
          expect(payload['link']).not_to include('/dictionaries/')
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

        it 'searches all public dictionaries (link is the un-scoped /find_ids)' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          payload = JSON.parse(json_response['result']['content'].first['text'])
          # No dictionary → link points at the global /find_ids form, not
          # /dictionaries/{dict}/find_ids.
          expect(payload['link']).to match(%r{/find_ids\?label=cancer\z})
          expect(payload['link']).not_to include('/dictionaries/')
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

    describe 'tools/call text_annotation' do
      let(:method_name) { 'tools/call' }

      context 'with valid text and dictionary — annotations found' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'The patient has cancer and diabetes.',
              'dictionaries' => dictionary.name
            }
          }
        end

        it 'POSTs JSON to /text_annotation.json and formats matched spans' do
          captured_request = nil
          allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
            captured_request = req
            mock_http_response(status: 200, body: {
              'text' => 'The patient has cancer and diabetes.',
              'denotations' => [
                { 'span' => { 'begin' => 16, 'end' => 22 }, 'obj' => '0004992' },
                { 'span' => { 'begin' => 27, 'end' => 35 }, 'obj' => '0005015' }
              ]
            })
          end

          post :streamable_http, body: jsonrpc_request.to_json

          # Wire-level assertions — POST + JSON body carries text + dictionaries
          expect(captured_request).to be_a(Net::HTTP::Post)
          expect(captured_request.path).to eq('/text_annotation.json')
          expect(captured_request['Content-Type']).to eq('application/json')
          body = JSON.parse(captured_request.body)
          expect(body['text']).to eq('The patient has cancer and diabetes.')
          expect(body['dictionaries']).to eq(dictionary.name)

          # Response formatting — JSON object with `annotation` (SIAF) and `link`.
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          result_text = json_response['result']['content'].first['text']
          payload = JSON.parse(result_text)

          expect(payload.keys).to match_array(%w[annotation link])
          expect(payload['annotation']).to include('The patient has [cancer][0004992] and [diabetes][0005015].')
          # URL reference block at the tail (extended SIAF)
          expect(payload['annotation']).to include("[0004992]: 0004992")
          expect(payload['annotation']).to include("[0005015]: 0005015")
          expect(payload['link']).to match(%r{/text_annotation\?text=.*&dictionaries=#{dictionary.name}})
        end
      end

      context 'with real UBERON-style URLs — SIAF short-ID extraction + URL ref block' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'The eye and the brain are connected via the optic nerve.',
              'dictionaries' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: {
              'text' => 'The eye and the brain are connected via the optic nerve.',
              'denotations' => [
                { 'span' => { 'begin' => 4,  'end' => 7 },  'obj' => 'http://purl.obolibrary.org/obo/UBERON_0000019' },
                { 'span' => { 'begin' => 12, 'end' => 21 }, 'obj' => 'http://purl.obolibrary.org/obo/UBERON_0000955' },
                # Same span → pipe-merged into one label per extended spec
                { 'span' => { 'begin' => 44, 'end' => 55 }, 'obj' => 'http://purl.obolibrary.org/obo/UBERON_0000941' },
                { 'span' => { 'begin' => 44, 'end' => 55 }, 'obj' => 'http://purl.obolibrary.org/obo/UBERON_0004904' }
              ]
            })
          end
        end

        it 'inlines short IDs and appends the URL reference block' do
          post :streamable_http, body: jsonrpc_request.to_json
          text = JSON.parse(response.body)['result']['content'].first['text']

          # Inline body
          expected_inline = 'The [eye][UBERON_0000019] and [the brain][UBERON_0000955] are connected via the [optic nerve][UBERON_0000941|UBERON_0004904].'
          expect(text).to include(expected_inline)

          # URL reference block resolves each short ID back to the full URL
          expect(text).to include('[UBERON_0000019]: http://purl.obolibrary.org/obo/UBERON_0000019')
          expect(text).to include('[UBERON_0000955]: http://purl.obolibrary.org/obo/UBERON_0000955')
          expect(text).to include('[UBERON_0000941]: http://purl.obolibrary.org/obo/UBERON_0000941')
          expect(text).to include('[UBERON_0004904]: http://purl.obolibrary.org/obo/UBERON_0004904')
        end
      end

      context 'with valid input but no matches found' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'Nothing matches in this text.',
              'dictionaries' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: {
              'text' => 'Nothing matches in this text.',
              'denotations' => []
            })
          end
        end

        it 'returns the original text as the annotation value (unchanged, since nothing matched)' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          payload = JSON.parse(json_response['result']['content'].first['text'])
          # No matches → SIAF has nothing to inline, so `annotation` is the
          # input text verbatim. LLM can infer "zero matches" from the absence
          # of any [...][...] structure in the value.
          expect(payload['annotation']).to eq('Nothing matches in this text.')
          expect(payload['link']).to be_present
        end
      end

      context 'with missing text' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => { 'dictionaries' => dictionary.name }
          }
        end

        it 'returns isError with a clear message and does NOT hit the annotation endpoint' do
          expect_any_instance_of(Net::HTTP).not_to receive(:request)

          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Text is required')
        end
      end

      context 'with missing dictionaries' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => { 'text' => 'some text' }
          }
        end

        it 'returns isError before making the HTTP call' do
          expect_any_instance_of(Net::HTTP).not_to receive(:request)

          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('At least one dictionary')
        end
      end

      context 'when the annotation endpoint returns an upstream error' do
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'text',
              'dictionaries' => 'nonexistent_dict'
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 400, body: { 'message' => 'Dictionary not found: nonexistent_dict' })
          end
        end

        it 'surfaces the upstream error message via isError so the LLM can self-correct' do
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be true
          expect(json_response['result']['content'].first['text']).to include('Dictionary not found')
        end
      end

      context 'with a comma-separated list of dictionaries' do
        # Real users will annotate against multiple dictionaries at once.
        # Guards that we forward the CSV verbatim to the annotation endpoint
        # rather than accidentally splitting it into an array (which would
        # change the JSON body's shape and confuse the controller).
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'brain and heart',
              'dictionaries' => 'uberon,mondo,hpo'
            }
          }
        end

        it 'passes the raw CSV string in the JSON body without splitting' do
          captured_request = nil
          allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
            captured_request = req
            mock_http_response(status: 200, body: { 'text' => 'brain and heart', 'denotations' => [] })
          end

          post :streamable_http, body: jsonrpc_request.to_json

          body = JSON.parse(captured_request.body)
          expect(body['dictionaries']).to eq('uberon,mondo,hpo')
          expect(body['dictionaries']).to be_a(String)  # NOT an Array
        end
      end

      context 'with a denotation missing its span field (malformed upstream response)' do
        # Defensive: if the annotator ever returns a denotation without a span
        # (bug, protocol drift, or partial result), we should not crash — the
        # formatter falls back to empty snippet + [0-0] rather than raising.
        let(:params) do
          {
            'name' => 'text_annotation',
            'arguments' => {
              'text' => 'some biomedical text',
              'dictionaries' => dictionary.name
            }
          }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: {
              'text' => 'some biomedical text',
              'denotations' => [ { 'obj' => 'ID_WITHOUT_SPAN' } ]
            })
          end
        end

        it 'silently skips the malformed denotation instead of raising' do
          # Under SIAF, a denotation without a span can't be inlined anywhere,
          # so `build_siaf_source` filters it out. The `annotation` field ends
          # up as the plain input text — no ghost tag, no reference-block
          # entry, no crash.
          post :streamable_http, body: jsonrpc_request.to_json

          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['result']['isError']).to be_falsey
          payload = JSON.parse(json_response['result']['content'].first['text'])
          # Malformed obj must NOT leak into the SIAF output.
          expect(payload['annotation']).not_to include('ID_WITHOUT_SPAN')
          expect(payload['annotation']).to include('some biomedical text')
        end
      end
    end

    describe 'link field on tool responses' do
      # Every tool response includes a `link` key pointing at the matching
      # PubDictionaries HTML view. Route + query-string param names must
      # mirror the real forms under app/views/, otherwise the click-through
      # would 404 or not pre-fill correctly.
      let(:method_name) { 'tools/call' }

      def payload
        JSON.parse(JSON.parse(response.body)['result']['content'].first['text'])
      end

      context 'get_dictionary_description' do
        let(:params) do
          { 'name' => 'get_dictionary_description', 'arguments' => { 'name' => 'uberon' } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: 'anatomy ontology')
          end
        end

        it 'links to /dictionaries/{name}' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with('/dictionaries/uberon')
        end
      end

      context 'find_ids without dictionary → global /find_ids' do
        let(:params) do
          { 'name' => 'find_ids', 'arguments' => { 'labels' => 'cancer,diabetes' } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: { 'cancer' => [ '1' ], 'diabetes' => [ '2' ] })
          end
        end

        it 'links to the global find_ids page with label= (singular, matches the form)' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with('/find_ids?label=cancer%2Cdiabetes')
        end
      end

      context 'find_ids with dictionary → scoped find_ids page' do
        let(:params) do
          { 'name' => 'find_ids', 'arguments' => { 'labels' => 'cancer', 'dictionary' => dictionary.name } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: { 'cancer' => [ '1' ] })
          end
        end

        it 'links to /dictionaries/{dict}/find_ids' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with("/dictionaries/#{dictionary.name}/find_ids?label=cancer")
        end
      end

      context 'find_terms → per-dictionary find_terms page' do
        let(:params) do
          { 'name' => 'find_terms', 'arguments' => { 'ids' => '1,2', 'dictionary' => dictionary.name } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: { '1' => { 'label' => 'a', 'dictionary' => dictionary.name },
                                                     '2' => { 'label' => 'b', 'dictionary' => dictionary.name } })
          end
        end

        it 'links to /dictionaries/{dict}/find_terms with identifiers= (plural, matches the form)' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with("/dictionaries/#{dictionary.name}/find_terms?identifiers=1%2C2")
        end
      end

      context 'text_annotation with short text → text pre-filled in URL' do
        let(:params) do
          { 'name' => 'text_annotation',
            'arguments' => { 'text' => 'cancer', 'dictionaries' => dictionary.name } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: { 'text' => 'cancer', 'denotations' => [] })
          end
        end

        it 'includes both text= and dictionaries= in the URL' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with("/text_annotation?text=cancer&dictionaries=#{dictionary.name}")
        end
      end

      context 'text_annotation with long text → text omitted (URL too long)' do
        # Practical browser URL length is ~2K chars. Beyond that, click-through
        # would 4xx. We omit text but keep the dictionaries hint so the form
        # is pre-filtered when the user pastes their own text.
        let(:long_text) { 'A' * 2000 }
        let(:params) do
          { 'name' => 'text_annotation',
            'arguments' => { 'text' => long_text, 'dictionaries' => dictionary.name } }
        end

        before do
          allow_any_instance_of(Net::HTTP).to receive(:request) do
            mock_http_response(status: 200, body: { 'text' => long_text, 'denotations' => [] })
          end
        end

        it 'links to /text_annotation with dictionaries= only (no text= param)' do
          post :streamable_http, body: jsonrpc_request.to_json
          expect(payload['link']).to end_with("/text_annotation?dictionaries=#{dictionary.name}")
          expect(payload['link']).not_to include('text=')
        end
      end
    end

    describe 'tools/list' do
      # Guards discoverability: if text_annotation is dropped from the schema
      # (or its required fields change), the LLM can't find/call it correctly
      # even though execution would still work in isolation.
      let(:method_name) { 'tools/list' }
      let(:params)      { {} }

      it 'includes text_annotation with the correct required fields' do
        post :streamable_http, body: jsonrpc_request.to_json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        tools = json_response['result']['tools']

        tool = tools.find { |t| t['name'] == 'text_annotation' }
        expect(tool).not_to be_nil, "text_annotation missing from tools/list"
        expect(tool['inputSchema']['required']).to match_array(%w[text dictionaries])
        expect(tool['inputSchema']['properties']).to include('text', 'dictionaries')
      end

      it 'annotates every tool with the MCP hint booleans and a human-readable title' do
        # Guards the annotation contract end-to-end. llm_meta_server reads
        # these into mcp_tools.annotations and renders Read-only / Destructive
        # / Open-world badges from them.
        #
        # idempotentHint is intentionally OMITTED (not asserted false either)
        # because per the MCP spec it's only meaningful when destructiveHint
        # is true — for these read-only tools, clients may assume idempotence
        # and asserting it here would mislead badge-rendering UIs.
        post :streamable_http, body: jsonrpc_request.to_json

        tools = JSON.parse(response.body)['result']['tools']
        # All 6 current tools are read-only queries against the local DB.
        # If a future tool has different hints (e.g. a write endpoint), this
        # test should be relaxed to check per-tool rather than blanket.
        tools.each do |tool|
          ann = tool['annotations']
          expect(ann).to be_a(Hash), "#{tool['name']} is missing annotations"
          expect(ann['readOnlyHint']).to eq(true),      "#{tool['name']}: readOnlyHint should be true"
          expect(ann['destructiveHint']).to eq(false),  "#{tool['name']}: destructiveHint should be false"
          expect(ann['openWorldHint']).to eq(false),    "#{tool['name']}: openWorldHint should be false"
          expect(ann).not_to have_key('idempotentHint'), "#{tool['name']}: idempotentHint should not be set on read-only tools (see MCP spec)"
          expect(ann['title']).to be_a(String), "#{tool['name']}: title should be a String"
          expect(ann['title']).to be_present,   "#{tool['name']}: title should be non-empty"
        end
      end
    end
  end

  # ---- prompt and resource primitives ---------------------------------
  #
  # Added alongside tools to test whether one MCP server can usefully expose
  # all three primitive types (spike, 2026-09-20).
  describe 'prompt and resource primitives' do
    before { request.content_type = 'application/json' }

    def rpc(method, params = {})
      post :streamable_http, body: { jsonrpc: '2.0', id: 1, method: method, params: params }.to_json
      JSON.parse(response.body)
    end

    def stub_catalog
      allow_any_instance_of(Net::HTTP).to receive(:request) do
        mock_http_response(status: 200, body: [
          { 'name' => 'uberon', 'description' => 'Anatomy', 'maintainer' => 'admin', 'entries_num' => 3 }
        ])
      end
    end

    describe 'initialize' do
      it 'advertises all three primitive types' do
        caps = rpc('initialize', 'protocolVersion' => '2025-06-18',
                                 'clientInfo' => { 'name' => 'spec', 'version' => '1' })['result']['capabilities']

        expect(caps.keys).to include('tools', 'prompts', 'resources')
      end

      it 'still completes the handshake when the client sends no clientInfo' do
        response = rpc('initialize', 'protocolVersion' => '2025-06-18')

        expect(response['error']).to be_nil
        expect(response['result']['serverInfo']['name']).to eq('PubDictionaries')
      end
    end

    describe 'prompts/list' do
      it 'exposes annotate with its argument schema' do
        prompts = rpc('prompts/list')['result']['prompts']

        expect(prompts.map { _1['name'] }).to eq([ 'annotate' ])
        args = prompts.first['arguments']
        # `dictionaries` (CSV), not `dictionary_name`: the annotation page
        # selects a list, so a single-name argument could not be auto-filled.
        expect(args.map { _1['name'] }).to eq([ 'text', 'dictionaries' ])
        expect(args.map { _1['required'] }).to eq([ true, true ])
      end
    end

    describe 'prompts/get' do
      it 'materialises a user message with both arguments substituted' do
        result = rpc('prompts/get', 'name' => 'annotate',
                                    'arguments' => { 'text' => 'Gastric mucosa.', 'dictionaries' => 'uberon,mondo' })['result']

        message = result['messages'].first
        expect(result['messages'].size).to eq(1)
        expect(message['role']).to eq('user')
        # Structured content, per spec — NOT a bare string.
        expect(message['content']['type']).to eq('text')
        expect(message['content']['text']).to include('Gastric mucosa.').and include('uberon,mondo')
      end

      it 'rejects an unknown prompt with invalid params' do
        error = rpc('prompts/get', 'name' => 'nope')['error']

        expect(error['code']).to eq(-32602)
      end

      it 'rejects a missing required argument, naming it' do
        error = rpc('prompts/get', 'name' => 'annotate', 'arguments' => { 'text' => 'x' })['error']

        expect(error['code']).to eq(-32602)
        expect(error['message']).to include('dictionaries')
      end
    end

    describe 'resources/list' do
      it 'exposes the catalog resource' do
        stub_catalog
        resource = rpc('resources/list')['result']['resources'].first

        expect(resource['uri']).to eq('pubdictionaries://dictionaries')
        expect(resource['mimeType']).to eq('application/json')
      end

      # Prototype of the io.modelcontextprotocol/static-primitives extension.
      # The prefix is reserved for official extensions, which is what this is
      # a prototype of; a third-party field would need its own vendor prefix.
      it 'declares the static-primitives extension fields' do
        stub_catalog
        meta = rpc('resources/list')['result']['resources'].first['_meta']
        fields = meta['io.modelcontextprotocol/static-primitives']

        expect(meta.keys).to eq([ 'io.modelcontextprotocol/static-primitives' ])
        expect(fields['sizeBytes']).to be > 0
        expect(fields['volatility']).to eq('stable')
        expect(fields['autoAttach']).to be(true)
      end

      # volatility and autoAttach replaced the single attachmentHint enum.
      # The old key must not survive anywhere: a client seeing both shapes
      # would have to guess which one the server means.
      it 'no longer emits the superseded attachmentHint key' do
        stub_catalog
        fields = rpc('resources/list')['result']['resources'].first
                   .dig('_meta', 'io.modelcontextprotocol/static-primitives')

        expect(fields).not_to have_key('attachmentHint')
        expect(fields.keys).to match_array(%w[sizeBytes volatility autoAttach])
      end

      # sizeBytes exists so a client can decide whether to attach the
      # resource BEFORE fetching it. A count that disagrees with the real
      # payload would make that decision on a fiction, so compare bytes.
      it 'advertises the exact byte length of what resources/read returns' do
        stub_catalog
        advertised = rpc('resources/list')['result']['resources'].first
                       .dig('_meta', 'io.modelcontextprotocol/static-primitives', 'sizeBytes')
        payload = rpc('resources/read', 'uri' => 'pubdictionaries://dictionaries')['result']['contents'].first['text']

        expect(advertised).to eq(payload.bytesize)
      end
    end

    describe 'resources/read' do
      it 'returns the catalog as JSON text' do
        stub_catalog
        contents = rpc('resources/read', 'uri' => 'pubdictionaries://dictionaries')['result']['contents'].first

        expect(contents['mimeType']).to eq('application/json')
        expect(JSON.parse(contents['text'])['dictionaries'].first['name']).to eq('uberon')
      end

      # The resource and the list_dictionaries tool must not drift: they are
      # two envelopes over one payload, and a client should not get a
      # different answer depending on which primitive it used.
      it 'carries the same payload as the list_dictionaries tool' do
        stub_catalog
        from_resource = JSON.parse(rpc('resources/read', 'uri' => 'pubdictionaries://dictionaries')['result']['contents'].first['text'])
        from_tool = JSON.parse(rpc('tools/call', 'name' => 'list_dictionaries', 'arguments' => {})['result']['content'].first['text'])

        expect(from_resource).to eq(from_tool)
      end

      it 'rejects an unknown uri with invalid params' do
        expect(rpc('resources/read', 'uri' => 'pubdictionaries://nope')['error']['code']).to eq(-32602)
      end
    end

    # Previously every protocol-level failure surfaced as -32603 (internal
    # error), so a client probing for optional primitives could not tell
    # "unsupported" from "broken".
    describe 'an unsupported method' do
      it 'is reported as method-not-found, not internal error' do
        error = rpc('completions/complete')['error']

        expect(error['code']).to eq(-32601)
        expect(error['message']).to include('completions/complete')
      end
    end
  end
end
