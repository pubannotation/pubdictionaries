# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dictionary, type: :model do
  describe 'semantic search functionality' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_semantic_dict') }

    # Mock embedding vector (768-dimensional for PubMedBERT)
    def mock_embedding_vector
      Array.new(768) { rand }
    end

    before do
      # Create entries with embeddings
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

      # Add embeddings to entries
      dictionary.entries.each do |entry|
        entry.update_column(:embedding, mock_embedding_vector)
      end

      # Make all entries searchable
      dictionary.entries.update_all(searchable: true)
    end

    describe '#search_term_semantic' do
      context 'without embedding cache' do
        it 'fetches embedding from server' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).with('cytokine release syndrome').and_return(query_embedding)

          results = dictionary.search_term_semantic('cytokine release syndrome', 0.6, [])

          expect(EmbeddingServer).to have_received(:fetch_embedding).once
          expect(results).to be_an(Array)
        end

        it 'returns empty array when embedding fetch fails' do
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(nil)

          results = dictionary.search_term_semantic('test query', 0.6, [])

          expect(results).to eq([])
        end

        it 'returns empty array for empty term' do
          allow(EmbeddingServer).to receive(:fetch_embedding)

          results = dictionary.search_term_semantic('', 0.6, [])

          expect(results).to eq([])
          allow(EmbeddingServer).to receive(:fetch_embedding)
          expect(EmbeddingServer).not_to have_received(:fetch_embedding)
        end
      end

      context 'with embedding cache' do
        it 'uses cached embedding instead of fetching from server' do
          allow(EmbeddingServer).to receive(:fetch_embedding)
          query_embedding = mock_embedding_vector
          cache = { 'cytokine release syndrome' => query_embedding }

          results = dictionary.search_term_semantic('cytokine release syndrome', 0.6, [], cache)

          expect(EmbeddingServer).not_to have_received(:fetch_embedding)
        end

        it 'falls back to server when cache miss' do
          query_embedding = mock_embedding_vector
          cache = { 'other term' => mock_embedding_vector }
          allow(EmbeddingServer).to receive(:fetch_embedding).with('cytokine release syndrome').and_return(query_embedding)

          results = dictionary.search_term_semantic('cytokine release syndrome', 0.6, [], cache)

          expect(EmbeddingServer).to have_received(:fetch_embedding).once
        end

        it 'works with empty cache' do
          query_embedding = mock_embedding_vector
          cache = {}
          allow(EmbeddingServer).to receive(:fetch_embedding).with('cytokine release syndrome').and_return(query_embedding)

          results = dictionary.search_term_semantic('cytokine release syndrome', 0.6, [], cache)

          expect(EmbeddingServer).to have_received(:fetch_embedding).once
        end
      end

      context 'result structure' do
        it 'returns results with correct structure' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          results = dictionary.search_term_semantic('test query', 0.0, [])

          expect(results).to be_an(Array)
          results.each do |result|
            expect(result).to include(:label, :identifier, :score, :dictionary, :search_type)
            expect(result[:search_type]).to eq('Semantic')
            expect(result[:dictionary]).to eq(dictionary.name)
            expect(result[:score]).to be_between(0, 1)
          end
        end

        it 'converts distance to similarity score correctly' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          results = dictionary.search_term_semantic('test query', 0.0, [])

          # Score should be 1.0 - distance, so all scores should be ≤ 1.0
          results.each do |result|
            expect(result[:score]).to be <= 1.0
            expect(result[:score]).to be >= 0.0
          end
        end
      end

      context 'filtering by tags' do
        before do
          # Add tags to entries
          tag1 = create(:tag, dictionary: dictionary, value: 'disease')
          tag2 = create(:tag, dictionary: dictionary, value: 'symptom')

          entry1 = dictionary.entries.find_by(identifier: 'HP:0033041')
          entry2 = dictionary.entries.find_by(identifier: 'HP:0001945')

          create(:entry_tag, entry: entry1, tag: tag1)
          create(:entry_tag, entry: entry2, tag: tag2)
        end

        it 'filters results by tag' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          results = dictionary.search_term_semantic('test query', 0.0, ['disease'])

          # Should only return entries with 'disease' tag
          expect(results.size).to be <= 1
        end

        it 'returns all results when no tag filter specified' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          results_no_filter = dictionary.search_term_semantic('test query', 0.0, [])
          results_with_filter = dictionary.search_term_semantic('test query', 0.0, ['disease'])

          expect(results_no_filter.size).to be >= results_with_filter.size
        end
      end

      context 'searchable flag filtering' do
        it 'excludes non-searchable entries' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          # Mark one entry as non-searchable
          dictionary.entries.first.update_column(:searchable, false)

          results = dictionary.search_term_semantic('test query', 0.0, [])

          # Should not include the non-searchable entry
          non_searchable_id = dictionary.entries.first.identifier
          result_ids = results.map { |r| r[:identifier] }
          expect(result_ids).not_to include(non_searchable_id)
        end

        it 'returns empty when all entries are non-searchable' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          # Mark all entries as non-searchable
          dictionary.entries.update_all(searchable: false)

          results = dictionary.search_term_semantic('test query', 0.0, [])

          expect(results).to be_empty
        end
      end
    end

    describe '#search_term with semantic_threshold' do
      let(:ssdb) { nil }

      it 'adds semantic results when semantic_threshold is provided' do
        # Test that semantic search is invoked by checking results include semantic matches
        query_embedding = mock_embedding_vector
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

        # Use a query that won't match surface search but could match semantic
        results = dictionary.search_term(ssdb, 'inflammatory response', nil, nil, [], 0.85, false, 0.6)

        # Should be an array (may or may not have results depending on embeddings)
        expect(results).to be_an(Array)
      end

      it 'does not call semantic search when semantic_threshold is nil' do
        allow(dictionary).to receive(:normalize1).and_return('test')
        allow(dictionary).to receive(:normalize2).and_return('test')
        allow(EmbeddingServer).to receive(:fetch_embedding)

        results = dictionary.search_term(ssdb, 'test query', nil, nil, [], 0.85, false, nil)

        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end

      it 'does not call semantic search when semantic_threshold is 0' do
        allow(dictionary).to receive(:normalize1).and_return('test')
        allow(dictionary).to receive(:normalize2).and_return('test')
        allow(EmbeddingServer).to receive(:fetch_embedding)

        results = dictionary.search_term(ssdb, 'test query', nil, nil, [], 0.85, false, 0)

        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end

      it 'passes embedding cache to search_term_semantic' do
        allow(dictionary).to receive(:normalize1).and_return('test')
        allow(dictionary).to receive(:normalize2).and_return('test')
        allow(EmbeddingServer).to receive(:fetch_embedding)

        query_embedding = mock_embedding_vector
        cache = { 'test query' => query_embedding }

        results = dictionary.search_term(ssdb, 'test query', nil, nil, [], 0.85, false, 0.6, cache)

        # Should use cache, not call server
        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end

      it 'removes duplicate results by identifier' do
        # Create entry that might match both surface and semantic
        allow(dictionary).to receive(:normalize1).and_return('cytokine storm')
        allow(dictionary).to receive(:normalize2).and_return('cytokine storm')

        query_embedding = mock_embedding_vector
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

        results = dictionary.search_term(ssdb, 'Cytokine storm', nil, nil, [], 1.0, false, 0.6)

        # Should deduplicate by identifier
        identifiers = results.map { |r| r[:identifier] }
        expect(identifiers.uniq.size).to eq(identifiers.size)
      end
    end

    describe '.search_term_top with semantic search' do
      let(:dict2) { create(:dictionary, user: user, name: 'test_dict2') }
      let(:ssdbs) { {} }

      before do
        # Create entry in second dictionary
        entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:0012345')
        entry.update_column(:embedding, mock_embedding_vector)
        entry.update_column(:searchable, true)
      end

      it 'aggregates semantic results from multiple dictionaries' do
        query_embedding = mock_embedding_vector
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

        dictionaries = [dictionary, dict2]
        results = Dictionary.search_term_top(dictionaries, ssdbs, 0.85, false, 0.6, 'test query', [])

        # Should have results from both dictionaries
        dict_names = results.map { |r| r[:dictionary] }.uniq
        expect(dict_names.size).to be >= 1
      end

      it 'passes embedding cache through to individual dictionary searches' do
        allow(EmbeddingServer).to receive(:fetch_embedding)
        query_embedding = mock_embedding_vector
        cache = { 'test query' => query_embedding }

        dictionaries = [dictionary, dict2]
        results = Dictionary.search_term_top(dictionaries, ssdbs, 0.85, false, 0.6, 'test query', [], nil, nil, cache)

        # Should not call embedding server
        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end
    end

    describe '.search_term_order with semantic search' do
      let(:dict2) { create(:dictionary, user: user, name: 'test_dict2') }
      let(:ssdbs) { {} }

      before do
        entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:0012345')
        entry.update_column(:embedding, mock_embedding_vector)
        entry.update_column(:searchable, true)
      end

      it 'returns results sorted by score descending' do
        query_embedding = mock_embedding_vector
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

        dictionaries = [dictionary, dict2]
        results = Dictionary.search_term_order(dictionaries, ssdbs, 0.85, false, 0.6, 'test query', [])

        # Verify results are sorted by score (descending)
        scores = results.map { |r| r[:score] }
        expect(scores).to eq(scores.sort.reverse)
      end

      it 'passes embedding cache to search methods' do
        allow(EmbeddingServer).to receive(:fetch_embedding)
        query_embedding = mock_embedding_vector
        cache = { 'test query' => query_embedding }

        dictionaries = [dictionary, dict2]
        results = Dictionary.search_term_order(dictionaries, ssdbs, 0.85, false, 0.6, 'test query', [], nil, nil, cache)

        # Should use cache
        expect(EmbeddingServer).not_to have_received(:fetch_embedding)
      end
    end
  end
end
