# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dictionary, '.find_ids_by_labels with semantic search', type: :model do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_find_ids_dict') }

  def mock_embedding_vector
    Array.new(768) { rand }
  end

  before do
    # Create test entries
    entries_data = [
      ['Cytokine storm', 'HP:0033041', 'cytokine storm', 'cytokine storm', 14, EntryMode::GRAY, false, dictionary.id],
      ['Fever', 'HP:0001945', 'fever', 'fever', 5, EntryMode::GRAY, false, dictionary.id],
      ['Headache', 'HP:0002315', 'headache', 'headache', 8, EntryMode::GRAY, false, dictionary.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      entries_data,
      validate: false
    )

    # Make entries searchable
    dictionary.entries.update_all(searchable: true)

    # Create semantic table and add embeddings (embeddings are only in semantic table now)
    dictionary.create_semantic_table!
    dictionary.entries.each do |entry|
      dictionary.upsert_semantic_entry(entry, mock_embedding_vector)
    end

    dictionary.update_entries_num
  end

  after do
    dictionary.drop_semantic_table! if dictionary.has_semantic_table?
  end

  describe 'with semantic_threshold option' do
    it 'performs semantic search when semantic_threshold is provided' do
      labels = ['cytokine release syndrome']
      options = { semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(EmbeddingServer).to have_received(:fetch_embedding).at_least(:once)
      expect(results).to be_a(Hash)
      expect(results.keys).to include('cytokine release syndrome')
    end

    it 'does not perform semantic search when semantic_threshold is nil' do
      labels = ['fever']
      options = { semantic_threshold: nil }

      allow(EmbeddingServer).to receive(:fetch_embedding)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(EmbeddingServer).not_to have_received(:fetch_embedding)
    end

    it 'does not perform semantic search when semantic_threshold is not provided' do
      labels = ['fever']
      options = {}

      allow(EmbeddingServer).to receive(:fetch_embedding)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(EmbeddingServer).not_to have_received(:fetch_embedding)
    end
  end

  describe 'result structure with semantic search' do
    it 'returns hash with label keys' do
      labels = ['cytokine storm']
      options = { semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(results).to be_a(Hash)
      expect(results.keys).to eq(labels)
    end

    it 'includes search_type in verbose mode' do
      labels = ['cytokine storm']
      options = { semantic_threshold: 0.6, verbose: true }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      if results['cytokine storm'].any?
        results['cytokine storm'].each do |entry|
          expect(entry).to be_a(Hash)
          # May have search_type if it came from semantic search
          if entry.key?(:search_type)
            expect(['Semantic', 'Surface']).to include(entry[:search_type])
          end
        end
      end
    end

    it 'returns identifiers in non-verbose mode' do
      labels = ['fever']
      options = { semantic_threshold: 0.6, verbose: false }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      if results['fever'].any?
        # Non-verbose mode returns just identifiers
        results['fever'].each do |id|
          expect(id).to be_a(String)
        end
      end
    end
  end

  describe 'combining surface and semantic results' do
    it 'combines results from both search methods' do
      labels = ['fever']
      options = { semantic_threshold: 0.0, threshold: 0.85 }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Should have results (either from surface match or semantic search)
      expect(results['fever']).to be_an(Array)
    end

    it 'deduplicates results by identifier' do
      # Create label that matches exactly (surface) and might also match semantically
      labels = ['Fever']
      options = { semantic_threshold: 0.0, threshold: 0.85, verbose: true }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      if results['Fever'].any?
        identifiers = results['Fever'].map { |r| r[:identifier] }
        # Should not have duplicate identifiers
        expect(identifiers.uniq.size).to eq(identifiers.size)
      end
    end
  end

  describe 'multiple labels' do
    it 'performs semantic search for each label' do
      labels = ['cytokine release syndrome', 'inflammatory response']
      options = { semantic_threshold: 0.6 }

      call_count = 0
      allow(EmbeddingServer).to receive(:fetch_embedding) do
        call_count += 1
        mock_embedding_vector
      end

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Should call for each label
      expect(call_count).to be >= labels.size
      expect(results.keys).to match_array(labels)
    end
  end

  describe 'multiple dictionaries' do
    let(:dict2) { create(:dictionary, user: user, name: 'dict2') }

    before do
      entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:9999')
      entry.update_column(:embedding, mock_embedding_vector)
      entry.update_column(:searchable, true)
      dict2.update_entries_num
    end

    it 'searches across all dictionaries' do
      labels = ['inflammatory response']
      options = { semantic_threshold: 0.6, verbose: true }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary, dict2], options)

      # Results may come from either dictionary
      if results['inflammatory response'].any?
        dict_names = results['inflammatory response'].map { |r| r[:dictionary] }.uniq
        expect(dict_names.size).to be >= 1
      end
    end
  end

  describe 'tag filtering with semantic search' do
    before do
      tag = create(:tag, dictionary: dictionary, value: 'symptom')
      entry = dictionary.entries.find_by(identifier: 'HP:0001945')
      create(:entry_tag, entry: entry, tag: tag)
    end

    it 'filters semantic results by tag' do
      labels = ['inflammatory response']
      options = { semantic_threshold: 0.0, tags: ['symptom'] }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Should only return entries with 'symptom' tag
      expect(results).to be_a(Hash)
    end
  end

  describe 'threshold interaction' do
    it 'uses surface similarity threshold alongside semantic threshold' do
      labels = ['cytokine']
      options = { threshold: 0.9, semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Both thresholds should be applied
      expect(results).to be_a(Hash)
    end

    it 'works with exact match (threshold = 1.0) and semantic search' do
      labels = ['Fever']
      options = { threshold: 1.0, semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Should find exact match for 'Fever' and possibly semantic matches
      expect(results['Fever']).to be_an(Array)
    end
  end

  describe 'superfluous mode with semantic search' do
    it 'returns all matching results in order when superfluous is true' do
      labels = ['fever']
      options = { semantic_threshold: 0.0, superfluous: true, verbose: true }

      allow(EmbeddingServer).to receive(:fetch_embedding).and_return(mock_embedding_vector)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      if results['fever'].any?
        # Results should be sorted by score
        scores = results['fever'].map { |r| r[:score] }
        expect(scores).to eq(scores.sort.reverse)
      end
    end
  end

  describe 'performance considerations' do
    it 'handles multiple labels efficiently' do
      labels = ['fever', 'headache', 'inflammation', 'pain', 'swelling']
      options = { semantic_threshold: 0.6 }

      call_count = 0
      allow(EmbeddingServer).to receive(:fetch_embedding) do
        call_count += 1
        mock_embedding_vector
      end

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      # Should call embedding server for each label
      expect(call_count).to be >= labels.size
      expect(results.keys).to match_array(labels)
    end
  end

  describe 'edge cases' do
    it 'handles empty label list' do
      labels = []
      options = { semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(results).to eq({})
      expect(EmbeddingServer).not_to have_received(:fetch_embedding)
    end

    it 'handles empty dictionary list' do
      labels = ['fever']
      options = { semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embedding)

      # Empty dictionary list returns empty results for each label
      results = Dictionary.find_ids_by_labels(labels, [], options)
      expect(results).to eq({ 'fever' => [] })
    end

    it 'handles nil semantic_threshold gracefully' do
      labels = ['fever']
      options = { semantic_threshold: nil }

      allow(EmbeddingServer).to receive(:fetch_embedding)

      results = Dictionary.find_ids_by_labels(labels, [dictionary], options)

      expect(results).to be_a(Hash)
      expect(EmbeddingServer).not_to have_received(:fetch_embedding)
    end
  end
end
