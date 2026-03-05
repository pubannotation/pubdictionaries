# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobsController, type: :controller do
  before { @request.env["devise.mapping"] = Devise.mappings[:user] }

  describe 'GET #index' do
    context 'when not signed in' do
      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when signed in as a regular user' do
      let(:user) { create(:user) }

      it 'raises not authorized' do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(user)
        expect { get :index }.to raise_error('Not authorized.')
      end
    end

    context 'when signed in as an expert user' do
      let(:user) { create(:user, :expert) }

      it 'raises not authorized' do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(user)
        expect { get :index }.to raise_error('Not authorized.')
      end
    end

    context 'when signed in as an admin user' do
      let(:user) { create(:user, :admin) }

      it 'renders successfully' do
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(user)
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end
end
