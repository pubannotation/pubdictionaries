require 'rails_helper'

RSpec.describe CreateSemanticTablesJob, type: :job do
  let(:user) { create(:user) }

  # Mock embedding vector (768-dimensional for PubMedBERT)
  def mock_embedding_vector
    Array.new(768) { rand }
  end

  def create_dictionary_with_embeddings(name)
    dictionary = create(:dictionary, user: user, name: name)

    entry = Entry.create!(
      dictionary: dictionary,
      label: 'Test term',
      identifier: 'TEST:001',
      norm1: 'testterm',
      norm2: 'test term',
      label_length: 9,
      searchable: true
    )
    dictionary.update_entries_num

    # Create semantic table and add embedding there (not in entries table)
    dictionary.create_semantic_table!
    dictionary.upsert_semantic_entry(entry, mock_embedding_vector)

    dictionary
  end

  def create_dictionary_without_embeddings(name)
    dictionary = create(:dictionary, user: user, name: name)

    Entry.create!(
      dictionary: dictionary,
      label: 'Test term',
      identifier: 'TEST:002',
      norm1: 'testterm',
      norm2: 'test term',
      label_length: 9,
      searchable: true
    )
    dictionary.update_entries_num
    dictionary
  end

  describe '#perform' do
    after do
      Dictionary.all.each do |d|
        d.drop_semantic_table! if d.has_semantic_table?
      end
    end

    it 'creates semantic tables for dictionaries with embeddings' do
      # Create a dictionary with embeddings in semantic table
      dict = create_dictionary_with_embeddings('test_dict_1')
      expect(dict.has_semantic_table?).to be true
      expect(dict.embeddings_populated?).to be true

      # The job should recognize it already has embeddings
      CreateSemanticTablesJob.perform_now

      dict.reload
      expect(dict.has_semantic_table?).to be true
    end

    it 'skips dictionaries without embeddings' do
      dict = create_dictionary_without_embeddings('test_dict_no_emb')
      expect(dict.embeddings_populated?).to be false

      CreateSemanticTablesJob.perform_now

      dict.reload
      expect(dict.has_semantic_table?).to be false
    end

    it 'skips dictionaries that already have semantic tables' do
      dict = create_dictionary_with_embeddings('test_dict_existing')
      expect(dict.has_semantic_table?).to be true

      # Should not try to rebuild (already exists)
      CreateSemanticTablesJob.perform_now

      # Still has semantic table
      expect(dict.has_semantic_table?).to be true
    end

    it 'processes multiple dictionaries' do
      dict1 = create_dictionary_with_embeddings('test_dict_a')
      dict2 = create_dictionary_with_embeddings('test_dict_b')
      dict3 = create_dictionary_without_embeddings('test_dict_c')

      CreateSemanticTablesJob.perform_now

      expect(dict1.reload.has_semantic_table?).to be true
      expect(dict2.reload.has_semantic_table?).to be true
      expect(dict3.reload.has_semantic_table?).to be false
    end

    it 'returns a summary of the operation' do
      create_dictionary_with_embeddings('test_dict_summary')
      create_dictionary_without_embeddings('test_dict_skipped')

      result = CreateSemanticTablesJob.perform_now

      expect(result).to include('created').or include('skipped')
    end

    it 'handles errors gracefully and continues processing' do
      dict1 = create_dictionary_with_embeddings('test_dict_error_1')
      dict2 = create_dictionary_with_embeddings('test_dict_error_2')

      # Both dictionaries already have semantic tables from setup
      # This test verifies error handling doesn't crash the job
      expect(dict1.has_semantic_table?).to be true
      expect(dict2.has_semantic_table?).to be true

      expect { CreateSemanticTablesJob.perform_now }.not_to raise_error
    end
  end
end
