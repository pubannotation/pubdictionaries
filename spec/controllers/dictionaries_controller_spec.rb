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
end
