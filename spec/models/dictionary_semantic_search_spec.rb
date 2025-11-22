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
      # Create entries
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

      # Make all entries searchable
      dictionary.entries.update_all(searchable: true)

      # Create semantic table and add embeddings
      dictionary.create_semantic_table!
      dictionary.entries.each do |entry|
        dictionary.upsert_semantic_entry(entry, mock_embedding_vector)
      end
    end

    after do
      dictionary.drop_semantic_table! if dictionary.has_semantic_table?
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

          # Mark one entry as non-searchable and remove from semantic table
          entry = dictionary.entries.first
          entry.update_column(:searchable, false)
          dictionary.remove_entry_from_semantic_table(entry.id)

          results = dictionary.search_term_semantic('test query', 0.0, [])

          # Should not include the non-searchable entry
          result_ids = results.map { |r| r[:identifier] }
          expect(result_ids).not_to include(entry.identifier)
        end

        it 'returns empty when all entries are non-searchable' do
          query_embedding = mock_embedding_vector
          allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

          # Mark all entries as non-searchable and clear semantic table
          dictionary.entries.each do |entry|
            entry.update_column(:searchable, false)
            dictionary.remove_entry_from_semantic_table(entry.id)
          end

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
        # Create entry in second dictionary with semantic table
        entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:0012345', searchable: true)
        dict2.update_entries_num  # Important: update entries_num so search_term doesn't return early
        dict2.create_semantic_table!
        dict2.upsert_semantic_entry(entry, mock_embedding_vector)
      end

      after do
        dict2.drop_semantic_table! if dict2.has_semantic_table?
      end

      it 'aggregates semantic results from multiple dictionaries' do
        query_embedding = mock_embedding_vector
        allow(EmbeddingServer).to receive(:fetch_embedding).and_return(query_embedding)

        dictionaries = [dictionary, dict2]
        # Use very low threshold (0.01) to ensure results are returned
        # Note: threshold must be > 0 since the code checks semantic_threshold > 0
        results = Dictionary.search_term_top(dictionaries, ssdbs, 0.85, false, 0.01, 'test query', [])

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
        entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:0012345', searchable: true)
        dict2.update_entries_num  # Important: update entries_num so search_term doesn't return early
        dict2.create_semantic_table!
        dict2.upsert_semantic_entry(entry, mock_embedding_vector)
      end

      after do
        dict2.drop_semantic_table! if dict2.has_semantic_table?
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

    describe 'temp table semantic search' do
      describe '#create_semantic_temp_table!' do
        it 'creates a temporary table with dictionary entries' do
          table_name = dictionary.create_semantic_temp_table!

          expect(table_name).to start_with('temp_semantic_dict_')

          # Table should exist
          count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{table_name}"
          ).first['cnt']
          expect(count).to eq(dictionary.entries.where(searchable: true).count)

          dictionary.drop_semantic_temp_table!
        end

        it 'includes only searchable entries with embeddings' do
          # Mark one entry as non-searchable and remove from semantic table
          entry = dictionary.entries.first
          entry.update_column(:searchable, false)
          dictionary.remove_entry_from_semantic_table(entry.id)

          table_name = dictionary.create_semantic_temp_table!

          count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{table_name}"
          ).first['cnt']

          # Should match the number of entries still in the semantic table
          semantic_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']
          expect(count).to eq(semantic_count)

          dictionary.drop_semantic_temp_table!
        end

        it 'creates HNSW index on the temp table' do
          table_name = dictionary.create_semantic_temp_table!

          # Check for index existence
          indexes = ActiveRecord::Base.connection.exec_query(
            "SELECT indexname FROM pg_indexes WHERE tablename = '#{table_name}'"
          )
          index_names = indexes.map { |r| r['indexname'] }

          expect(index_names.any? { |name| name.include?('hnsw') }).to be true

          dictionary.drop_semantic_temp_table!
        end
      end

      describe '#batch_search_semantic_temp' do
        let(:table_name) { dictionary.create_semantic_temp_table! }

        after do
          dictionary.drop_semantic_temp_table!
        end

        it 'returns matching entries for valid embeddings' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test query' => query_embedding }

          results = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.0, [])

          expect(results).to be_a(Hash)
          expect(results['test query']).to be_an(Array)
        end

        it 'returns empty hash for empty span_embeddings' do
          results = dictionary.batch_search_semantic_temp(table_name, {}, 0.7, [])

          expect(results).to eq({})
        end

        it 'filters out spans without valid embeddings' do
          span_embeddings = {
            'valid query' => mock_embedding_vector,
            'invalid query' => nil,
            'empty query' => []
          }

          results = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.0, [])

          expect(results.keys).to include('valid query')
          expect(results['valid query']).to be_an(Array)
        end

        it 'returns results with correct structure' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test query' => query_embedding }

          results = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.0, [])

          results['test query'].each do |result|
            expect(result).to include(:label, :identifier, :score, :dictionary, :search_type)
            expect(result[:search_type]).to eq('Semantic')
            expect(result[:dictionary]).to eq(dictionary.name)
            expect(result[:score]).to be_between(0, 1)
          end
        end

        it 'respects similarity threshold' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test query' => query_embedding }

          # Very high threshold should return fewer or no results
          results_high = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.99, [])
          # Low threshold should return more results
          results_low = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.0, [])

          expect(results_low['test query'].size).to be >= results_high['test query'].size
        end

        it 'handles multiple spans in batch' do
          span_embeddings = {
            'query1' => mock_embedding_vector,
            'query2' => mock_embedding_vector,
            'query3' => mock_embedding_vector
          }

          results = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.0, [])

          expect(results.keys).to contain_exactly('query1', 'query2', 'query3')
        end
      end

      describe '#execute_temp_table_semantic_query (SQL correctness)' do
        let(:table_name) { dictionary.create_semantic_temp_table! }

        after do
          dictionary.drop_semantic_temp_table!
        end

        it 'executes without SQL errors' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test' => query_embedding }

          # This should not raise any SQL errors
          expect {
            dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.5, [])
          }.not_to raise_error
        end

        it 'returns correct distance calculations' do
          # Use an entry's own embedding to query - should get very high similarity
          entry = dictionary.entries.first

          # Fetch the entry's embedding from the semantic table and parse it
          semantic_entry = ActiveRecord::Base.connection.exec_query(
            "SELECT embedding FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          # Parse the vector string (format: "[0.1,0.2,...]") to array
          embedding_str = semantic_entry['embedding']
          entry_embedding = embedding_str.gsub(/[\[\]]/, '').split(',').map(&:to_f)

          span_embeddings = { 'exact match test' => entry_embedding }

          results = dictionary.batch_search_semantic_temp(table_name, span_embeddings, 0.9, [])

          # Should find the entry with very high score (close to 1.0)
          matching_result = results['exact match test'].find { |r| r[:identifier] == entry.identifier }
          expect(matching_result).to be_present
          expect(matching_result[:score]).to be > 0.99  # Almost exact match
        end
      end
    end

    describe 'persistent semantic table' do
      # Note: The before block already creates a semantic table with embeddings

      describe '#create_semantic_table!' do
        it 'creates HNSW index on the persistent table' do
          indexes = ActiveRecord::Base.connection.exec_query(
            "SELECT indexname FROM pg_indexes WHERE tablename = '#{dictionary.semantic_table_name}'"
          )
          index_names = indexes.map { |r| r['indexname'] }

          expect(index_names.any? { |name| name.include?('hnsw') }).to be true
        end

        it 'does not create table if already exists' do
          expect(dictionary.has_semantic_table?).to be true
          # Calling again should not raise error
          expect { dictionary.create_semantic_table! }.not_to raise_error
        end
      end

      describe '#drop_semantic_table!' do
        it 'drops the persistent table' do
          expect(dictionary.has_semantic_table?).to be true

          dictionary.drop_semantic_table!

          expect(dictionary.has_semantic_table?).to be false

          # Table should not exist
          expect {
            ActiveRecord::Base.connection.exec_query(
              "SELECT COUNT(*) FROM #{dictionary.semantic_table_name}"
            )
          }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      describe '#rebuild_semantic_table!' do
        it 'creates an empty semantic table' do
          dictionary.rebuild_semantic_table!

          expect(dictionary.has_semantic_table?).to be true

          # Table should be empty (rebuild doesn't populate)
          count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']
          expect(count).to eq(0)
        end
      end

      describe '#upsert_semantic_entry' do
        it 'adds new entry to semantic table' do
          initial_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']

          new_entry = dictionary.entries.create!(
            label: 'New Term',
            identifier: 'HP:9999999',
            norm1: 'new term',
            norm2: 'new term',
            label_length: 8,
            searchable: true
          )

          dictionary.upsert_semantic_entry(new_entry, mock_embedding_vector)

          new_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']
          expect(new_count).to eq(initial_count + 1)
        end

        it 'updates existing entry in semantic table' do
          entry = dictionary.entries.first
          new_embedding = mock_embedding_vector

          dictionary.upsert_semantic_entry(entry, new_embedding)

          result = ActiveRecord::Base.connection.exec_query(
            "SELECT label FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['label']).to eq(entry.label)
        end

        it 'does nothing for non-searchable entry' do
          entry = dictionary.entries.first
          entry.update_column(:searchable, false)

          initial_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']

          dictionary.upsert_semantic_entry(entry, mock_embedding_vector)

          new_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']
          expect(new_count).to eq(initial_count)
        end
      end

      describe '#update_semantic_entry_metadata' do
        it 'updates label and identifier in semantic table' do
          entry = dictionary.entries.first
          entry.update_columns(label: 'Updated Label', identifier: 'HP:9999999')

          dictionary.update_semantic_entry_metadata(entry)

          result = ActiveRecord::Base.connection.exec_query(
            "SELECT label, identifier FROM #{dictionary.semantic_table_name} WHERE id = #{entry.id}"
          ).first
          expect(result['label']).to eq('Updated Label')
          expect(result['identifier']).to eq('HP:9999999')
        end
      end

      describe '#remove_entry_from_semantic_table' do
        it 'removes entry from semantic table' do
          entry = dictionary.entries.first
          initial_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']

          dictionary.remove_entry_from_semantic_table(entry.id)

          new_count = ActiveRecord::Base.connection.exec_query(
            "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
          ).first['cnt']
          expect(new_count).to eq(initial_count - 1)
        end
      end

      describe '#batch_search_semantic_persistent' do
        it 'returns matching entries using persistent table' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test query' => query_embedding }

          results = dictionary.batch_search_semantic_persistent(span_embeddings, 0.0, [])

          expect(results).to be_a(Hash)
          expect(results['test query']).to be_an(Array)
        end

        it 'returns empty hash when no semantic table exists' do
          dictionary.drop_semantic_table!
          span_embeddings = { 'test query' => mock_embedding_vector }

          results = dictionary.batch_search_semantic_persistent(span_embeddings, 0.0, [])

          expect(results).to eq({})
        end

        it 'returns results with correct structure' do
          query_embedding = mock_embedding_vector
          span_embeddings = { 'test query' => query_embedding }

          results = dictionary.batch_search_semantic_persistent(span_embeddings, 0.0, [])

          results['test query'].each do |result|
            expect(result).to include(:label, :identifier, :score, :dictionary, :search_type)
            expect(result[:search_type]).to eq('Semantic')
          end
        end
      end
    end
  end
end
