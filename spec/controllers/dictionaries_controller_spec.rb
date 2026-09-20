# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DictionariesController, type: :controller do
  before { @request.env["devise.mapping"] = Devise.mappings[:user] }

  describe 'POST #update_embeddings' do
    let(:owner) { create(:user) }
    let(:dictionary) { create(:dictionary, user: owner, name: 'test_embeddings_dict') }

    context 'when not signed in' do
      it 'redirects to sign in' do
        post :update_embeddings, params: { id: dictionary.name }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when signed in as a regular user (dictionary owner)' do
      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(owner)
      end

      it 'redirects with access denied' do
        post :update_embeddings, params: { id: dictionary.name }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Access denied')
      end
    end

    context 'when signed in as an expert user' do
      let(:expert_user) { create(:user, :expert) }
      let(:expert_dictionary) { create(:dictionary, user: expert_user, name: 'expert_dict') }

      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(expert_user)
        active_job = double('ActiveJob', create_job_record: nil)
        allow(UpdateDictionaryEmbeddingsJob).to receive(:perform_later).and_return(active_job)
      end

      it 'allows access to own dictionary' do
        post :update_embeddings, params: { id: expert_dictionary.name }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end
    end

    context 'when signed in as an admin user' do
      let(:admin_user) { create(:user, :admin) }

      before do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
        active_job = double('ActiveJob', create_job_record: nil)
        allow(UpdateDictionaryEmbeddingsJob).to receive(:perform_later).and_return(active_job)
      end

      it 'allows access to any dictionary' do
        post :update_embeddings, params: { id: dictionary.name }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end
    end
  end

  describe 'GET #index — query filter' do
    # Backbone of the LLM integration: /dictionaries?query=anatomy filters
    # both the JSON payload (consumed by the MCP list_dictionaries tool) and
    # the HTML grid (that the user clicks through to). Also accepts ?q= as an
    # alias so URLs typed by humans work either way.
    let(:owner) { create(:user) }
    before do
      create(:dictionary, user: owner, name: 'uberon',    description: 'anatomy ontology (uber-anatomy)', public: true)
      create(:dictionary, user: owner, name: 'mouse_ma', description: 'mouse anatomy ontology',        public: true)
      create(:dictionary, user: owner, name: 'mondo',     description: 'mondo disease ontology',        public: true)
      create(:dictionary, user: owner, name: 'private_d', description: 'anatomy but private',           public: false)
    end

    it 'filters JSON results to public dictionaries matching name or description' do
      get :index, params: { query: 'anatomy' }, format: :json

      json = JSON.parse(response.body)
      names = json.map { |d| d['name'] }
      expect(names).to match_array(%w[uberon mouse_ma])       # both match on "anatomy" in description
      expect(names).not_to include('mondo')             # doesn't match
      expect(names).not_to include('private_d')         # matches text but is not public
    end

    it 'accepts ?q= as an alias for ?query=' do
      get :index, params: { q: 'anatomy' }, format: :json

      names = JSON.parse(response.body).map { |d| d['name'] }
      expect(names).to match_array(%w[uberon mouse_ma])
    end

    it 'query wins when both ?query= and ?q= are supplied (query is the canonical form)' do
      get :index, params: { query: 'mondo', q: 'anatomy' }, format: :json

      names = JSON.parse(response.body).map { |d| d['name'] }
      expect(names).to eq(%w[mondo])
    end

    it 'matches names too, not just descriptions' do
      get :index, params: { query: 'uber' }, format: :json

      names = JSON.parse(response.body).map { |d| d['name'] }
      expect(names).to eq(%w[uberon])
    end

    it 'returns the full public list when no query is given (backward compat)' do
      get :index, format: :json

      names = JSON.parse(response.body).map { |d| d['name'] }
      expect(names).to match_array(%w[uberon mouse_ma mondo])   # no private_d
    end

    it 'safely handles SQL LIKE wildcards in user input (does not blow up or over-match)' do
      # % and _ are wildcards in LIKE — they must be escaped so a query like
      # "50%_off" doesn't accidentally match everything.
      get :index, params: { query: '%' }, format: :json

      # `%` is escaped to `\%` — literal percent is not present in any name/description,
      # so no dictionary matches. Without escaping, ALL public dictionaries would return.
      expect(JSON.parse(response.body)).to be_empty
    end
  end
end
