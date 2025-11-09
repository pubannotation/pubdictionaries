# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnnotationController, type: :controller do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_annotation_dict') }

  def mock_embedding_vector
    Array.new(768) { rand }
  end

  before do
    # Create test entries
    entries_data = [
      ['Cytokine storm', 'HP:0033041', 'cytokine storm', 'cytokine storm', 14, EntryMode::GRAY, false, dictionary.id],
      ['Fever', 'HP:0001945', 'fever', 'fever', 5, EntryMode::GRAY, false, dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      entries_data,
      validate: false
    )

    dictionary.entries.each do |entry|
      entry.update_column(:embedding, mock_embedding_vector)
      entry.update_column(:searchable, true)
    end

    dictionary.update_entries_num
  end

  describe 'GET #text_annotation with semantic similarity' do
    context 'with semantic_threshold parameter' do
      it 'passes semantic_threshold to TextAnnotator' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'cytokine release syndrome',
          dictionaries: dictionary.name,
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
        expect(assigns(:result)).to be_present
      end

      it 'handles use_semantic_similarity checkbox parameter' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          use_semantic_similarity: 'true',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
      end

      it 'does not use semantic search when semantic_threshold is not provided' do
        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name
        }

        expect(EmbeddingServer).not_to have_received(:fetch_embeddings)
        expect(response).to have_http_status(:success)
      end

      it 'does not use semantic search when semantic_threshold is empty string' do
        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          semantic_threshold: ''
        }

        expect(EmbeddingServer).not_to have_received(:fetch_embeddings)
        expect(response).to have_http_status(:success)
      end
    end

    context 'parameter parsing' do
      it 'parses semantic_threshold as float' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          semantic_threshold: '0.75'
        }

        permitted = assigns(:permitted)
        expect(permitted[:semantic_threshold]).to eq(0.75)
      end

      it 'handles semantic_threshold with use_semantic_similarity' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          use_semantic_similarity: '1',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
      end
    end

    context 'combining with other options' do
      it 'works with surface similarity threshold' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          threshold: '0.85',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
        result = assigns(:result)
        expect(result).to be_present
      end

      it 'works with longest option' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          longest: 'true',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
      end

      it 'works with tokens_len_max option' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          tokens_len_max: '4',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
      end

      it 'works with verbose option' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          verbose: 'true',
          semantic_threshold: '0.6'
        }

        expect(response).to have_http_status(:success)
        result = assigns(:result)
        expect(result[:denotations]).to be_an(Array)
      end
    end

    context 'JSON response' do
      it 'returns JSON when requested' do
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('application/json')
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('denotations')
      end
    end

    context 'error handling' do
      it 'handles embedding server errors gracefully' do
        allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(StandardError.new("Server error"))

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          semantic_threshold: '0.6'
        }

        # Should handle error (behavior depends on Rails.env)
        if Rails.env.development?
          expect { response }.to raise_error(StandardError)
        else
          expect(response).to have_http_status(:internal_server_error)
        end
      end

      it 'requires text parameter' do
        get :text_annotation, params: {
          dictionaries: dictionary.name,
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:bad_request)
      end

      it 'requires dictionary parameter' do
        get :text_annotation, params: {
          text: 'fever',
          semantic_threshold: '0.6'
        }

        if Rails.env.development?
          expect { response }.to raise_error(ArgumentError)
        else
          # In non-development, should return error
          expect(flash.now[:notice]).to be_present
        end
      end
    end
  end

  describe 'POST #text_annotation with semantic similarity' do
    it 'accepts semantic_threshold in POST request' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      post :text_annotation, params: {
        text: 'fever',
        dictionaries: dictionary.name,
        semantic_threshold: '0.6'
      }

      expect(response).to have_http_status(:success)
    end

    it 'handles JSON POST with semantic_threshold' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      post :text_annotation, params: {
        text: 'fever',
        dictionaries: dictionary.name,
        semantic_threshold: '0.6',
        format: :json
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('denotations')
    end
  end

  describe 'multiple dictionaries with semantic search' do
    let(:dict2) { create(:dictionary, user: user, name: 'dict2') }

    before do
      entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:9999')
      entry.update_column(:embedding, mock_embedding_vector)
      entry.update_column(:searchable, true)
      dict2.update_entries_num
    end

    it 'searches across multiple dictionaries' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      get :text_annotation, params: {
        text: 'inflammatory response',
        dictionaries: "#{dictionary.name},#{dict2.name}",
        semantic_threshold: '0.6'
      }

      expect(response).to have_http_status(:success)
      result = assigns(:result)
      expect(result).to be_present
    end
  end

  describe 'tag filtering with semantic search' do
    before do
      tag = create(:tag, dictionary: dictionary, value: 'symptom')
      entry = dictionary.entries.find_by(identifier: 'HP:0001945')
      create(:entry_tag, entry: entry, tag: tag)
    end

    it 'filters results by tag' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      get :text_annotation, params: {
        text: 'inflammatory response',
        dictionaries: dictionary.name,
        semantic_threshold: '0.6',
        tags: 'symptom'
      }

      expect(response).to have_http_status(:success)
    end
  end
end
