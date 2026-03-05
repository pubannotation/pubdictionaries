# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'user level methods' do
    describe '#admin?' do
      it 'returns true for admin users' do
        user = create(:user, :admin)
        expect(user.admin?).to be true
      end

      it 'returns false for expert users' do
        user = create(:user, :expert)
        expect(user.admin?).to be false
      end

      it 'returns false for regular users' do
        user = create(:user)
        expect(user.admin?).to be false
      end
    end

    describe '#expert?' do
      it 'returns true for admin users' do
        user = create(:user, :admin)
        expect(user.expert?).to be true
      end

      it 'returns true for expert users' do
        user = create(:user, :expert)
        expect(user.expert?).to be true
      end

      it 'returns false for regular users' do
        user = create(:user)
        expect(user.expert?).to be false
      end
    end

    describe '#regular?' do
      it 'returns false for admin users' do
        user = create(:user, :admin)
        expect(user.regular?).to be false
      end

      it 'returns false for expert users' do
        user = create(:user, :expert)
        expect(user.regular?).to be false
      end

      it 'returns true for regular users' do
        user = create(:user)
        expect(user.regular?).to be true
      end
    end
  end

  describe '#editable?' do
    let(:owner) { create(:user) }
    let(:other_user) { create(:user) }
    let(:admin_user) { create(:user, :admin) }

    it 'returns true when user is the owner' do
      expect(owner.editable?(owner)).to be true
    end

    it 'returns true when user is an admin' do
      expect(owner.editable?(admin_user)).to be true
    end

    it 'returns false when user is a different non-admin user' do
      expect(owner.editable?(other_user)).to be false
    end

    it 'returns falsey when user is nil' do
      expect(owner.editable?(nil)).to be_falsey
    end
  end

  describe 'factory traits' do
    it 'creates a regular user by default' do
      user = create(:user)
      expect(user.user_level).to eq(User::LEVEL_REGULAR)
    end

    it 'creates an admin user with :admin trait' do
      user = create(:user, :admin)
      expect(user.user_level).to eq(User::LEVEL_ADMIN)
    end

    it 'creates an expert user with :expert trait' do
      user = create(:user, :expert)
      expect(user.user_level).to eq(User::LEVEL_EXPERT)
    end
  end
end
