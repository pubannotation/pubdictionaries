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

    dictionary.entries.update_all(searchable: true)

    # Create semantic table and add embeddings there (not in entries table)
    dictionary.create_semantic_table!
    dictionary.entries.each do |entry|
      dictionary.upsert_semantic_entry(entry, mock_embedding_vector)
    end

    dictionary.update_entries_num
  end

  after do
    dictionary.drop_semantic_table! if dictionary.has_semantic_table?
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
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to be_present
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
        allow(EmbeddingServer).to receive(:fetch_embeddings)

        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name
        }

        expect(EmbeddingServer).not_to have_received(:fetch_embeddings)
        expect(response).to have_http_status(:success)
      end

      it 'does not use semantic search when semantic_threshold is empty string' do
        allow(EmbeddingServer).to receive(:fetch_embeddings)

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
          semantic_threshold: '0.75',
          format: :json
        }

        # Verify semantic search was invoked (meaning threshold was parsed correctly)
        expect(EmbeddingServer).to have_received(:fetch_embeddings).at_least(:once)
        expect(response).to have_http_status(:success)
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
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response).to be_present
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
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['denotations']).to be_an(Array)
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

        # When embedding server fails, the error propagates and results in 500
        get :text_annotation, params: {
          text: 'fever',
          dictionaries: dictionary.name,
          semantic_threshold: '0.6',
          format: :json
        }

        expect(response).to have_http_status(:internal_server_error)
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
      entry.update_column(:searchable, true)

      # Create semantic table and add embedding there
      dict2.create_semantic_table!
      dict2.upsert_semantic_entry(entry, mock_embedding_vector)
      dict2.update_entries_num
    end

    after do
      dict2.drop_semantic_table! if dict2.has_semantic_table?
    end

    it 'searches across multiple dictionaries' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      get :text_annotation, params: {
        text: 'inflammatory response',
        dictionaries: "#{dictionary.name},#{dict2.name}",
        semantic_threshold: '0.6',
        format: :json
      }

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response).to be_present
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

# Asking to annotate without choosing a dictionary is an ordinary mistake. It
# used to be raised as an ArgumentError, which the action's rescue turned into a
# flash notice — but only after `raise e if Rails.env.development?`. So the same
# submit answered 200 on production and 500 on the dev site, and the dev 500
# renders a Rails exception page, which carries no widget to restore a
# conversation into. That stopped being a curiosity when the assistant gained
# the ability to press Submit itself.
RSpec.describe AnnotationController, 'annotating with no dictionary chosen', type: :controller do
  # The test environment is not development, so the old code was rescued here
  # too and a plain request spec passed either way. Pretending to be
  # development is what makes this able to fail.
  def as_development
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
  end

  it 'renders the page with a notice instead of raising' do
    as_development

    expect { get :text_annotation, params: { text: 'I have a stomach ache.' } }.not_to raise_error
    expect(response).to have_http_status(:ok)
    expect(flash[:notice]).to match(/at least one dictionary/i)
  end

  # The JSON callers' contract is unchanged: this is still a bad request to them.
  it 'still answers 400 on the JSON path' do
    get :text_annotation, params: { text: 'I have a stomach ache.' }, format: :json

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)['message']).to match(/at least one dictionary/i)
  end

  it 'still answers 400 when no text was supplied at all' do
    get :text_annotation, params: {}, format: :json

    expect(response).to have_http_status(:bad_request)
  end
end
