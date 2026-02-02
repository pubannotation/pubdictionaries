# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LookupController, type: :controller do
  let(:user) { create(:user) }
  let(:public_dictionary) { create(:dictionary, user: user, name: 'public_dict', description: 'Public dictionary', public: true) }
  let(:private_dictionary) { create(:dictionary, user: user, name: 'private_dict', description: 'Private dictionary', public: false) }

  before do
    # Create test entries for public dictionary
    public_entries = [
      ['cancer', 'DOID:0004992', 'cancer', 'cancer', 6, EntryMode::GRAY, false, public_dictionary.id],
      ['diabetes', 'DOID:0005015', 'diabetes', 'diabetes', 8, EntryMode::GRAY, false, public_dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      public_entries,
      validate: false
    )

    # Create test entries for private dictionary
    private_entries = [
      ['secret term', 'PRIV:001', 'secret term', 'secret term', 11, EntryMode::GRAY, false, private_dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      private_entries,
      validate: false
    )

    public_dictionary.entries.update_all(searchable: true)
    private_dictionary.entries.update_all(searchable: true)
    public_dictionary.update_entries_num
    private_dictionary.update_entries_num
  end

  describe 'GET #find_ids' do
    context 'with dictionary specified' do
      it 'searches only in the specified dictionary' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids, params: { labels: 'cancer', dictionaries: public_dictionary.name }, format: :json
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result['cancer']).to be_present
      end
    end

    context 'without dictionary specified' do
      it 'searches in all public dictionaries' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids, params: { labels: 'cancer' }, format: :json
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result['cancer']).to be_present
      end

      it 'uses all public dictionaries when none specified' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids, params: { labels: 'cancer' }, format: :json

        expect(Dictionary).to have_received(:find_ids_by_labels) do |labels, dicts, opts|
          expect(labels).to eq(['cancer'])
          # Should only include public dictionaries
          expect(dicts.all?(&:public)).to be true
          expect(dicts.map(&:name)).to include('public_dict')
          expect(dicts.map(&:name)).not_to include('private_dict')
        end
      end
    end

    context 'without labels' do
      it 'returns bad request for JSON format' do
        get :find_ids, params: { dictionaries: public_dictionary.name }, format: :json
        expect(response).to have_http_status(:bad_request)
      end

      it 'returns empty result for HTML format' do
        get :find_ids, params: { dictionaries: public_dictionary.name }, format: :html
        expect(response).to have_http_status(:ok)
      end

      it 'does not call find_ids_by_labels when no labels provided' do
        allow(Dictionary).to receive(:find_ids_by_labels)

        get :find_ids, format: :html

        expect(Dictionary).not_to have_received(:find_ids_by_labels)
      end
    end

    context 'with empty dictionaries parameter' do
      it 'searches all public dictionaries when dictionaries param is empty string' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids, params: { labels: 'cancer', dictionaries: '' }, format: :json

        expect(Dictionary).to have_received(:find_ids_by_labels) do |labels, dicts, opts|
          expect(dicts.all?(&:public)).to be true
          expect(dicts.map(&:name)).to include('public_dict')
        end
      end
    end
  end

  describe 'GET #find_ids_api' do
    context 'with dictionary specified' do
      it 'searches only in the specified dictionary' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids_api, params: { labels: 'cancer', dictionaries: public_dictionary.name }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('DOID:0004992')
      end
    end

    context 'without dictionary specified' do
      it 'searches in all public dictionaries' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids_api, params: { labels: 'cancer' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('DOID:0004992')
      end

      it 'uses all public dictionaries when none specified' do
        allow(Dictionary).to receive(:find_ids_by_labels).and_return({ 'cancer' => ['DOID:0004992'] })

        get :find_ids_api, params: { labels: 'cancer' }

        expect(Dictionary).to have_received(:find_ids_by_labels) do |labels, dicts|
          expect(labels).to eq(['cancer'])
          # Should only include public dictionaries
          expect(dicts.all?(&:public)).to be true
          expect(dicts.map(&:name)).to include('public_dict')
          expect(dicts.map(&:name)).not_to include('private_dict')
        end
      end
    end

    context 'without labels' do
      it 'returns bad request' do
        get :find_ids_api, params: { dictionaries: public_dictionary.name }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET #find_terms' do
    context 'with dictionary specified' do
      it 'returns labels for the given identifiers' do
        # find_labels_by_ids returns arrays of hashes, which get transformed with .first
        allow(Dictionary).to receive(:find_labels_by_ids).and_return({
          'DOID:0004992' => [{ label: 'cancer', dictionary: public_dictionary.name }]
        })

        get :find_terms, params: { identifiers: 'DOID:0004992', dictionaries: public_dictionary.name }, format: :json
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result['DOID:0004992']['label']).to eq('cancer')
      end
    end

    context 'without dictionary specified' do
      it 'returns bad request because dictionary is required for find_terms' do
        get :find_terms, params: { identifiers: 'DOID:0004992' }, format: :json
        expect(response).to have_http_status(:bad_request)
        result = JSON.parse(response.body)
        expect(result['message']).to include('dictionary')
      end
    end

    context 'without identifiers' do
      it 'returns bad request for JSON format' do
        get :find_terms, params: { dictionaries: public_dictionary.name }, format: :json
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
