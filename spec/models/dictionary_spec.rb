# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dictionary, type: :model do
  describe '#empty_entries' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user) }

    context 'when mode is nil (delete all entries)' do
      let!(:gray_entry) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry) { create(:entry, :white, dictionary: dictionary) }
      let!(:black_entry) { create(:entry, :black, dictionary: dictionary) }
      let!(:auto_expanded_entry) { create(:entry, :auto_expanded, dictionary: dictionary) }
      let!(:tag) { create(:tag, dictionary: dictionary) }
      let!(:entry_tag) { create(:entry_tag, entry: gray_entry, tag: tag) }

      before do
        # Reload dictionary to get accurate entries_num
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'deletes all entries' do
        expect {
          dictionary.empty_entries(nil)
        }.to change { dictionary.entries.count }.from(4).to(0)
      end

      it 'deletes all entry_tags' do
        expect {
          dictionary.empty_entries(nil)
        }.to change { EntryTag.where(entry_id: [gray_entry.id, white_entry.id, black_entry.id, auto_expanded_entry.id]).count }.from(1).to(0)
      end

      it 'updates entries_num to 0' do
        dictionary.empty_entries(nil)
        dictionary.reload
        expect(dictionary.entries_num).to eq(0)
      end

      it 'calls clean_sim_string_db' do
        expect(dictionary).to receive(:clean_sim_string_db)
        dictionary.empty_entries(nil)
      end

      it 'performs operations within a transaction' do
        expect(dictionary).to receive(:transaction).and_call_original
        dictionary.empty_entries(nil)
      end
    end

    context 'when mode is EntryMode::GRAY' do
      let!(:gray_entry1) { create(:entry, :gray, dictionary: dictionary) }
      let!(:gray_entry2) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry) { create(:entry, :white, dictionary: dictionary) }
      let!(:black_entry) { create(:entry, :black, dictionary: dictionary) }
      let!(:auto_expanded_entry) { create(:entry, :auto_expanded, dictionary: dictionary) }

      before do
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'deletes only gray entries' do
        expect {
          dictionary.empty_entries(EntryMode::GRAY)
        }.to change { dictionary.entries.gray.count }.from(2).to(0)
      end

      it 'does not delete white entries' do
        expect {
          dictionary.empty_entries(EntryMode::GRAY)
        }.not_to change { dictionary.entries.white.count }
      end

      it 'does not delete black entries' do
        expect {
          dictionary.empty_entries(EntryMode::GRAY)
        }.not_to change { dictionary.entries.black.count }
      end

      it 'does not delete auto_expanded entries' do
        expect {
          dictionary.empty_entries(EntryMode::GRAY)
        }.not_to change { dictionary.entries.auto_expanded.count }
      end

      it 'updates entries_num' do
        initial_entries_num = dictionary.entries_num
        dictionary.empty_entries(EntryMode::GRAY)
        dictionary.reload
        # entries_num should reflect the removal of gray entries
        expect(dictionary.entries_num).to be < initial_entries_num
      end
    end

    context 'when mode is EntryMode::WHITE' do
      let!(:gray_entry) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry1) { create(:entry, :white, dictionary: dictionary) }
      let!(:white_entry2) { create(:entry, :white, dictionary: dictionary) }
      let!(:black_entry) { create(:entry, :black, dictionary: dictionary) }

      before do
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'destroys only white entries' do
        expect {
          dictionary.empty_entries(EntryMode::WHITE)
        }.to change { dictionary.entries.white.count }.from(2).to(0)
      end

      it 'does not delete gray entries' do
        expect {
          dictionary.empty_entries(EntryMode::WHITE)
        }.not_to change { dictionary.entries.gray.count }
      end

      it 'does not delete black entries' do
        expect {
          dictionary.empty_entries(EntryMode::WHITE)
        }.not_to change { dictionary.entries.black.count }
      end

      it 'uses bulk delete without triggering callbacks' do
        # Verify optimized implementation: delete_all skips callbacks
        # update_entries_num should be called exactly once at the end
        expect(dictionary).to receive(:update_entries_num).once
        dictionary.empty_entries(EntryMode::WHITE)
      end
    end

    context 'when mode is EntryMode::BLACK' do
      let!(:gray_entry) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry) { create(:entry, :white, dictionary: dictionary) }
      let!(:black_entry1) { create(:entry, :black, dictionary: dictionary) }
      let!(:black_entry2) { create(:entry, :black, dictionary: dictionary) }

      before do
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'cancels all black entries to gray' do
        expect {
          dictionary.empty_entries(EntryMode::BLACK)
        }.to change { dictionary.entries.black.count }.from(2).to(0)
      end

      it 'converts black entries to gray entries' do
        initial_gray_count = dictionary.entries.gray.count
        dictionary.empty_entries(EntryMode::BLACK)
        expect(dictionary.entries.gray.count).to eq(initial_gray_count + 2)
      end

      it 'does not affect white entries' do
        expect {
          dictionary.empty_entries(EntryMode::BLACK)
        }.not_to change { dictionary.entries.white.count }
      end

      it 'does not affect gray entries' do
        initial_gray_ids = dictionary.entries.gray.pluck(:id)
        dictionary.empty_entries(EntryMode::BLACK)
        # Original gray entries should still exist
        expect(dictionary.entries.where(id: initial_gray_ids, mode: EntryMode::GRAY).count).to eq(initial_gray_ids.count)
      end

      it 'uses bulk update instead of iterating entries' do
        # Verify the optimized implementation: should NOT call cancel_black
        expect(dictionary).not_to receive(:cancel_black)
        dictionary.empty_entries(EntryMode::BLACK)
      end

      it 'updates entries_num' do
        expect {
          dictionary.empty_entries(EntryMode::BLACK)
          dictionary.reload
        }.to change { dictionary.entries_num }
      end
    end

    context 'when mode is EntryMode::AUTO_EXPANDED' do
      let!(:gray_entry) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry) { create(:entry, :white, dictionary: dictionary) }
      let!(:auto_expanded_entry1) { create(:entry, :auto_expanded, dictionary: dictionary) }
      let!(:auto_expanded_entry2) { create(:entry, :auto_expanded, dictionary: dictionary) }

      before do
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'destroys only auto_expanded entries' do
        expect {
          dictionary.empty_entries(EntryMode::AUTO_EXPANDED)
        }.to change { dictionary.entries.auto_expanded.count }.from(2).to(0)
      end

      it 'does not delete gray entries' do
        expect {
          dictionary.empty_entries(EntryMode::AUTO_EXPANDED)
        }.not_to change { dictionary.entries.gray.count }
      end

      it 'does not delete white entries' do
        expect {
          dictionary.empty_entries(EntryMode::AUTO_EXPANDED)
        }.not_to change { dictionary.entries.white.count }
      end

      it 'uses bulk delete without triggering callbacks' do
        # Verify optimized implementation: delete_all skips callbacks
        # update_entries_num should be called exactly once at the end
        expect(dictionary).to receive(:update_entries_num).once
        dictionary.empty_entries(EntryMode::AUTO_EXPANDED)
      end
    end

    context 'when mode is invalid' do
      it 'raises ArgumentError with unexpected mode value' do
        expect {
          dictionary.empty_entries(999)
        }.to raise_error(ArgumentError, "Unexpected mode: 999")
      end

      it 'raises ArgumentError with string mode' do
        expect {
          dictionary.empty_entries("invalid")
        }.to raise_error(ArgumentError, "Unexpected mode: invalid")
      end
    end

    context 'transaction behavior' do
      let!(:gray_entry) { create(:entry, :gray, dictionary: dictionary) }
      let!(:white_entry) { create(:entry, :white, dictionary: dictionary) }

      it 'rolls back changes if an error occurs' do
        allow(dictionary).to receive(:update_entries_num).and_raise(StandardError, "Update failed")

        expect {
          dictionary.empty_entries(nil) rescue nil
        }.not_to change { dictionary.entries.count }
      end
    end

    context 'with entries having tags' do
      let!(:tag1) { create(:tag, dictionary: dictionary, value: "disease") }
      let!(:tag2) { create(:tag, dictionary: dictionary, value: "protein") }
      let!(:entry_with_tags) { create(:entry, :gray, dictionary: dictionary) }
      let!(:entry_tag1) { create(:entry_tag, entry: entry_with_tags, tag: tag1) }
      let!(:entry_tag2) { create(:entry_tag, entry: entry_with_tags, tag: tag2) }

      before do
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'deletes associated entry_tags when deleting all entries' do
        expect {
          dictionary.empty_entries(nil)
        }.to change { EntryTag.count }.by(-2)
      end

      it 'deletes all tags in the dictionary' do
        expect {
          dictionary.empty_entries(nil)
        }.to change { dictionary.tags.count }.from(2).to(0)
      end
    end
  end

  describe '#destroy safety check' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user) }

    context 'when dictionary has entries' do
      before do
        create(:entry, :gray, dictionary: dictionary)
        create(:entry, :white, dictionary: dictionary)
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'returns false when attempting to destroy' do
        expect(dictionary.destroy).to eq(false)
      end

      it 'adds error message to the model' do
        dictionary.destroy
        expect(dictionary.errors[:base]).to include(match(/Cannot destroy dictionary with entries/))
        expect(dictionary.errors[:base].first).to include("Please empty all entries first using empty_entries(nil)")
        expect(dictionary.errors[:base].first).to include("Current entries count: #{dictionary.entries_num}")
      end

      it 'does not destroy the dictionary' do
        expect {
          dictionary.destroy
        }.not_to change { Dictionary.count }
      end

      it 'preserves entries when destroy fails' do
        initial_count = dictionary.entries.count
        dictionary.destroy
        expect(dictionary.entries.count).to eq(initial_count)
      end
    end

    context 'when dictionary has many entries' do
      before do
        # Create 100 entries
        entries_data = Array.new(100) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::GRAY, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'shows correct entry count in error message' do
        dictionary.destroy
        expect(dictionary.errors[:base].first).to include("Current entries count: #{dictionary.entries_num}")
        expect(dictionary.entries_num).to eq(100)
      end
    end

    context 'when dictionary is empty' do
      before do
        # Ensure dictionary has no entries
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'allows destruction of empty dictionary' do
        expect(dictionary.entries.count).to eq(0)
        expect {
          dictionary.destroy
        }.to change { Dictionary.count }.by(-1)
      end

      it 'does not raise any exception' do
        expect {
          dictionary.destroy
        }.not_to raise_error
      end
    end

    context 'after emptying entries' do
      before do
        create(:entry, :gray, dictionary: dictionary)
        create(:entry, :white, dictionary: dictionary)
        create(:entry, :black, dictionary: dictionary)
        dictionary.update_entries_num
        dictionary.reload
      end

      it 'allows destruction after calling empty_entries(nil)' do
        # First empty all entries
        dictionary.empty_entries(nil)
        dictionary.reload

        # Now destruction should succeed
        expect {
          dictionary.destroy
        }.to change { Dictionary.count }.by(-1)
      end

      it 'does not raise exception after emptying' do
        dictionary.empty_entries(nil)
        dictionary.reload

        expect {
          dictionary.destroy
        }.not_to raise_error
      end
    end

    context 'integration with dependent associations' do
      let!(:tag) { create(:tag, dictionary: dictionary) }

      it 'destroys empty dictionary with tags' do
        # Dictionary has tags but no entries
        expect(dictionary.entries.count).to eq(0)
        expect(dictionary.tags.count).to be > 0

        expect {
          dictionary.destroy
        }.to change { Dictionary.count }.by(-1)
      end

      it 'does not destroy dictionary with entries even if it has tags' do
        create(:entry, :gray, dictionary: dictionary)
        dictionary.update_entries_num
        dictionary.reload

        expect(dictionary.destroy).to eq(false)
        expect(dictionary.errors[:base]).to include(match(/Cannot destroy dictionary with entries/))
      end
    end
  end

  describe '.by_query scope' do
    # Case-insensitive substring against name OR description; blank returns
    # everything. Chainable with other scopes (that's the point of a scope).
    let(:user) { create(:user) }
    let!(:uberon) { create(:dictionary, user: user, name: 'uberon', description: 'anatomical terms from uberon', public: true) }
    let!(:mondo)  { create(:dictionary, user: user, name: 'mondo',  description: 'disease ontology',              public: true) }
    let!(:hpo)    { create(:dictionary, user: user, name: 'HPO',    description: 'human phenotype ontology',      public: true) }

    it 'matches on name (case-insensitive)' do
      expect(Dictionary.by_query('MONDO')).to match_array([ mondo ])
      expect(Dictionary.by_query('uber')).to match_array([ uberon ])
    end

    it 'matches on description' do
      expect(Dictionary.by_query('anatomical')).to match_array([ uberon ])
    end

    it 'returns all rows when the query is blank / whitespace / nil' do
      # Contract: blank input is a no-op, so callers can chain unconditionally.
      expect(Dictionary.by_query(nil).count).to  eq(3)
      expect(Dictionary.by_query('').count).to   eq(3)
      expect(Dictionary.by_query('   ').count).to eq(3)
    end

    it 'composes with other scopes (e.g. .index_dictionaries)' do
      private_ana = create(:dictionary, user: user, name: 'priv_anat', description: 'anatomy but private', public: false)
      expect(Dictionary.index_dictionaries.by_query('anatom')).to include(uberon)
      expect(Dictionary.index_dictionaries.by_query('anatom')).not_to include(private_ana)
    end

    it 'escapes SQL LIKE wildcards in user input' do
      # A raw '%' would match everything without escaping — we should get 0 rows
      # since no name/description contains a literal percent sign.
      expect(Dictionary.by_query('%')).to be_empty
    end
  end
end
