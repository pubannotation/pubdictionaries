# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entry, type: :model do
  describe 'semantic table sync callbacks' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_sync_dict') }

    # Mock embedding vector (768-dimensional for PubMedBERT)
    def mock_embedding_vector
      Array.new(768) { rand }
    end

    before do
      # Create initial entries (without embeddings - embeddings are in semantic table only)
      entries_data = [
        ['Fever', 'HP:0001945', 'fever', 'fever', 5, EntryMode::GRAY, false, dictionary.id],
        ['Headache', 'HP:0002315', 'headache', 'headache', 8, EntryMode::GRAY, false, dictionary.id]
      ]
      Entry.bulk_import(
        [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
        entries_data,
        validate: false
      )

      # Make all entries searchable
      dictionary.entries.update_all(searchable: true)

      # Create semantic table and add embeddings directly
      dictionary.create_semantic_table!

      # Add entries with embeddings to semantic table
      dictionary.entries.each do |entry|
        dictionary.upsert_semantic_entry(entry, mock_embedding_vector)
      end
    end

    after do
      dictionary.drop_semantic_table! if dictionary.has_semantic_table?
    end

    describe 'after_save callback' do
      context 'when label changes' do
        it 'syncs entry metadata to semantic table' do
          entry = dictionary.entries.first
          new_label = 'Updated Fever'

          entry.update!(label: new_label)

          # Verify label was updated in semantic table
          result = ActiveRecord::Base.connection.exec_query(
            "SELECT label FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['label']).to eq(new_label)
        end
      end

      context 'when identifier changes' do
        it 'syncs entry metadata to semantic table' do
          entry = dictionary.entries.first
          new_identifier = 'HP:9999999'

          entry.update!(identifier: new_identifier)

          # Verify identifier was updated in semantic table
          result = ActiveRecord::Base.connection.exec_query(
            "SELECT identifier FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['identifier']).to eq(new_identifier)
        end
      end

      context 'when searchable changes to false' do
        it 'updates searchable flag in semantic table' do
          entry = dictionary.entries.first

          # Verify entry is initially searchable
          initial_result = ActiveRecord::Base.connection.exec_query(
            "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(initial_result['searchable']).to be true

          entry.update!(searchable: false)

          # Verify searchable was updated in semantic table
          result = ActiveRecord::Base.connection.exec_query(
            "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['searchable']).to be false
        end
      end

      context 'when searchable changes to true' do
        it 'updates searchable flag in semantic table' do
          entry = dictionary.entries.first

          # First mark as non-searchable
          entry.update!(searchable: false)

          # Verify it's non-searchable in semantic table
          result = ActiveRecord::Base.connection.exec_query(
            "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['searchable']).to be false

          # Now mark as searchable again
          entry.update!(searchable: true)

          # Verify searchable was updated in semantic table
          result = ActiveRecord::Base.connection.exec_query(
            "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['searchable']).to be true
        end
      end

      context 'when dictionary has no semantic table' do
        it 'does not raise error' do
          dictionary.drop_semantic_table!
          entry = dictionary.entries.first

          expect { entry.update!(label: 'New Label') }.not_to raise_error
        end
      end

      context 'when unrelated field changes' do
        it 'does not sync to semantic table' do
          entry = dictionary.entries.first

          # Change a field that doesn't affect semantic table
          expect(dictionary).not_to receive(:update_semantic_entry_metadata)

          entry.update_column(:dirty, true)
        end
      end
    end

    describe 'after_destroy callback' do
      it 'removes entry from semantic table' do
        entry = dictionary.entries.first

        initial_count = ActiveRecord::Base.connection.exec_query(
          "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
        ).first['cnt']

        entry.destroy

        new_count = ActiveRecord::Base.connection.exec_query(
          "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
        ).first['cnt']
        expect(new_count).to eq(initial_count - 1)
      end

      it 'does not raise error when dictionary has no semantic table' do
        dictionary.drop_semantic_table!
        entry = dictionary.entries.first

        expect { entry.destroy }.not_to raise_error
      end
    end

    describe '#update_embedding' do
      before do
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)
      end

      it 'fetches embedding and stores in semantic table' do
        entry = dictionary.entries.first

        result = entry.update_embedding

        expect(result).to be true
        expect(EmbeddingServer).to have_received(:fetch_embedding).with(entry.label)

        # Verify embedding was stored in semantic table
        result = ActiveRecord::Base.connection.exec_query(
          "SELECT embedding FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
        ).first
        expect(result).to be_present
      end

      it 'returns false when entry is not searchable' do
        entry = dictionary.entries.first
        entry.update_column(:searchable, false)

        result = entry.update_embedding

        expect(result).to be false
        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end

      it 'returns false when embedding server returns nil' do
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(nil)
        entry = dictionary.entries.first

        result = entry.update_embedding

        expect(result).to be false
      end
    end
  end
end
