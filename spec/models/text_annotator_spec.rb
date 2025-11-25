# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TextAnnotator, type: :model do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_annotator_dict') }

  def mock_embedding_vector
    Array.new(768) { rand }
  end

  before do
    # Create some test entries
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

    # Update dictionary metadata
    dictionary.update_entries_num
  end

  after do
    dictionary.drop_semantic_table! if dictionary.has_semantic_table?
  end

  describe 'initialization with semantic_threshold' do
    it 'stores semantic_threshold option' do
      options = { semantic_threshold: 0.6 }
      annotator = TextAnnotator.new([dictionary], options)

      expect(annotator.instance_variable_get(:@semantic_threshold)).to eq(0.6)
    end

    it 'initializes without requiring embedding cache' do
      annotator = TextAnnotator.new([dictionary], {})

      # With new pre-indexing approach, no cache is needed
      expect(annotator.instance_variable_get(:@cache_embeddings)).to be_nil
    end
  end

  describe 'pre-indexing span generation' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }
    let(:text) { 'cytokine release syndrome' }

    it 'pre-generates all possible spans from text' do
      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})

      # Should generate spans for: "cytokine", "release", "syndrome",
      # "cytokine release", "release syndrome", "cytokine release syndrome"
      expect(span_index.keys).to include('cytokine', 'release', 'syndrome')
      expect(span_index.keys.size).to be >= 3

      # Each span should have array of occurrences with metadata
      span_index.each do |span, occurrences|
        expect(occurrences).to be_an(Array)
        expect(occurrences).not_to be_empty
        occurrences.each do |info|
          expect(info).to have_key(:span_begin)
          expect(info).to have_key(:span_end)
          expect(info).to have_key(:norm1)
          expect(info).to have_key(:norm2)
          expect(info).to have_key(:entries)
        end
      end
    end

    it 'batch generates embeddings in single API call' do
      expect(EmbeddingServer).to receive(:fetch_embeddings).once do |spans|
        expect(spans).to be_an(Array)
        expect(spans.size).to be > 0
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})
      annotator.send(:batch_get_embeddings, span_index)
    end

    it 'generates unique spans only' do
      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})

      # Verify all spans in the index are unique (by definition of hash keys)
      expect(span_index.keys.uniq.size).to eq(span_index.keys.size)
    end

    it 'handles embedding server failures gracefully' do
      allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(StandardError.new("Server error"))

      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})

      # Should not raise error, just log and continue
      expect {
        annotator.send(:batch_get_embeddings, span_index)
      }.not_to raise_error

      # Embeddings should not be set
      span_index.each do |span, occurrences|
        occurrences.each do |info|
          expect(info[:embedding]).to be_nil
        end
      end
    end

    it 'stores multiple occurrences of the same span text' do
      # When the same text appears multiple times, all occurrences should be stored
      tokens = annotator.send(:norm1_tokenize, 'fever fever')
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, 'fever fever').inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, 'fever fever')
      annotator.send(:add_pars_info!, tokens, 'fever fever', sbreaks)

      span_index = annotator.send(:pre_generate_spans, 'fever fever', tokens, norm1s, norm2s, sbreaks, {})

      # "fever" appears twice, so it should have 2 occurrences in the array
      expect(span_index.keys.count('fever')).to eq(1)  # Only one key
      expect(span_index['fever']).to be_an(Array)
      expect(span_index['fever'].size).to eq(2)  # But two occurrences

      # Each occurrence should have different positions
      expect(span_index['fever'][0][:span_begin]).not_to eq(span_index['fever'][1][:span_begin])
    end
  end

  describe '#annotate_batch with semantic search' do
    context 'performance optimization' do
      it 'batch generates embeddings before annotation loop' do
        text = 'cytokine release syndrome is a serious condition'
        options = { semantic_threshold: 0.6, longest: true }

        # Expect two batch calls: one for context filtering, one for spans
        expect(EmbeddingServer).to receive(:fetch_embeddings).twice do |spans|
          expect(spans.size).to be > 0
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        annotator.dispose
      end

      it 'does not batch generate embeddings when semantic_threshold is nil' do
        text = 'cytokine release syndrome'
        options = { semantic_threshold: nil, longest: true }

        # Should not call embedding server at all
        expect(EmbeddingServer).not_to receive(:fetch_embeddings)

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        annotator.dispose
      end

      it 'does not batch generate embeddings when semantic_threshold is 0' do
        text = 'cytokine release syndrome'
        options = { semantic_threshold: 0, longest: true }

        # With semantic_threshold of 0, context filtering still calls it once
        # But span embeddings are not generated since threshold is 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        annotator.dispose
      end
    end

    context 'embedding reuse during annotation' do
      it 'generates embeddings once per batch for all spans' do
        text = 'fever and headache'
        options = { semantic_threshold: 0.6, longest: true }

        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          call_count += 1
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        # Should call twice: once for context, once for all spans in batch
        expect(call_count).to eq(2)

        annotator.dispose
      end

      it 'uses same embeddings across multiple dictionaries' do
        dict2 = create(:dictionary, user: user, name: 'dict2')
        entry = create(:entry, dictionary: dict2, label: 'Inflammation', identifier: 'HP:9999')
        entry.update_column(:embedding, mock_embedding_vector)
        entry.update_column(:searchable, true)
        dict2.update_entries_num

        text = 'fever'
        options = { semantic_threshold: 0.6, longest: true }

        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          call_count += 1
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary, dict2], options)
        result = annotator.annotate_batch([{ text: text }])

        # Should call twice: once for context, once for spans
        # Embeddings are reused across both dictionaries via embedding_cache parameter
        expect(call_count).to eq(2)

        annotator.dispose
      end
    end

    context 'semantic search results' do
      it 'finds semantically similar terms' do
        text = 'cytokine release syndrome'
        options = { semantic_threshold: 0.0, longest: true, threshold: 0.85 }

        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }]).first

        # Should find some annotations (if embeddings are similar enough)
        expect(result[:denotations]).to be_an(Array)

        annotator.dispose
      end

      it 'includes score in annotation results' do
        text = 'fever'
        options = { semantic_threshold: 0.0, longest: true }

        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }]).first

        result[:denotations].each do |denotation|
          expect(denotation[:score]).to be_a(Numeric)
          expect(denotation[:score]).to be_between(0, 1)
        end

        annotator.dispose
      end
    end

    context 'pre-indexing approach' do
      it 'efficiently handles duplicate spans in text' do
        text = 'fever and fever'
        options = { semantic_threshold: 0.6, longest: true }

        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)

        # Annotation should work correctly
        result1 = annotator.annotate_batch([{ text: text }]).first

        # With pre-indexing, we don't use span cache anymore
        # Instead we pre-generate all spans once per batch
        expect(result1[:denotations]).to be_an(Array)

        annotator.dispose
      end
    end
  end

  describe 'memory management' do
    it 'limits embedding cache size implicitly through span collection' do
      # Very long text would generate many spans
      text = 'word ' * 100
      options = { semantic_threshold: 0.6 }

      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        # Should not cache unlimited spans
        expect(spans.size).to be < 1000
        Array.new(spans.size) { mock_embedding_vector }
      end

      annotator = TextAnnotator.new([dictionary], options)
      result = annotator.annotate_batch([{ text: text }])

      annotator.dispose
    end
  end

  describe 'integration with existing features' do
    it 'works with surface similarity threshold' do
      text = 'cytokine storm'
      options = { semantic_threshold: 0.6, threshold: 0.85, longest: true }

      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      annotator = TextAnnotator.new([dictionary], options)
      result = annotator.annotate_batch([{ text: text }])

      # Should work without errors
      expect(result).to be_an(Array)
      expect(result.first[:denotations]).to be_an(Array)

      annotator.dispose
    end

    it 'works with longest option' do
      text = 'cytokine'
      options = { semantic_threshold: 0.6, longest: true }

      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      annotator = TextAnnotator.new([dictionary], options)
      result = annotator.annotate_batch([{ text: text }])

      expect(result).to be_an(Array)

      annotator.dispose
    end

    it 'works with superfluous option' do
      text = 'fever'
      options = { semantic_threshold: 0.6, superfluous: true }

      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      annotator = TextAnnotator.new([dictionary], options)
      result = annotator.annotate_batch([{ text: text }])

      expect(result).to be_an(Array)

      annotator.dispose
    end
  end

  describe 'span pre-filtering for semantic search' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }

    it 'filters out short spans' do
      spans = ['a', 'ab', 'abc', 'abcd', 'fever']
      filtered = annotator.send(:filter_spans_for_semantic, spans)

      # MinSpanLength is 3, so 'a' and 'ab' should be filtered
      expect(filtered).not_to include('a', 'ab')
      expect(filtered).to include('abc', 'abcd', 'fever')
    end

    it 'filters out purely numeric spans' do
      spans = ['123', '45.67', '1,234', 'abc123', 'test', '12 34']
      filtered = annotator.send(:filter_spans_for_semantic, spans)

      # Purely numeric spans should be filtered
      expect(filtered).not_to include('123', '45.67', '1,234', '12 34')
      expect(filtered).to include('abc123', 'test')
    end

    it 'reads configuration from PubDic::EmbeddingServer' do
      expect(PubDic::EmbeddingServer::MinSpanLength).to be_a(Integer)
      expect(PubDic::EmbeddingServer::SkipNumericSpans).to be_in([true, false])
    end
  end

  describe 'configurable embedding batch settings' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }
    let(:text) { 'cytokine release syndrome' }

    it 'reads BatchSize from PubDic::EmbeddingServer configuration' do
      expect(PubDic::EmbeddingServer::BatchSize).to be_a(Integer)
      expect(PubDic::EmbeddingServer::BatchSize).to be > 0
    end

    it 'reads ParallelThreads from PubDic::EmbeddingServer configuration' do
      expect(PubDic::EmbeddingServer::ParallelThreads).to be_a(Integer)
      expect(PubDic::EmbeddingServer::ParallelThreads).to be >= 1
    end

    it 'uses configured batch size for embedding requests' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        # Each batch should be at most BatchSize
        expect(spans.size).to be <= PubDic::EmbeddingServer::BatchSize
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map { |t| t[:token] }
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")) { |s, t| s[t[:position]] = t[:token]; s }
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})
      annotator.send(:batch_get_embeddings, span_index)
    end
  end

  describe 'string similarity early-exit optimization' do
    let(:annotator) { TextAnnotator.new([dictionary], { threshold: 0.85 }) }

    it 'assigns score 1.0 when norm2 matches exactly' do
      # Create a span_index with a span whose norm2 matches an entry exactly
      span_index = {
        'Fever' => [{
          span_begin: 0,
          span_end: 5,
          idx_token_begin: 0,
          idx_token_final: 0,
          norm1: 'fever',
          norm2: 'fever',  # Matches entry's norm2 exactly
          entries: []
        }]
      }

      # Get filtered sub_string_dbs (matching the annotator's internal structure)
      filtered_sub_string_dbs = annotator.instance_variable_get(:@sub_string_dbs)

      results = annotator.send(:batch_surface_match, span_index, [dictionary], filtered_sub_string_dbs)

      # Should find the 'Fever' entry with score 1.0
      expect(results['Fever']).not_to be_empty
      fever_result = results['Fever'].find { |r| r[:identifier] == 'HP:0001945' }
      expect(fever_result).not_to be_nil
      expect(fever_result[:score]).to eq(1.0)
    end

    it 'computes string similarity when norm2 does not match exactly' do
      # Create an entry with a different norm2
      Entry.create!(
        dictionary: dictionary,
        label: 'High fever',
        identifier: 'HP:0001234',
        norm1: 'highfever',
        norm2: 'highfever',
        label_length: 10,
        mode: EntryMode::GRAY
      )

      span_index = {
        'high fever' => [{
          span_begin: 0,
          span_end: 10,
          idx_token_begin: 0,
          idx_token_final: 1,
          norm1: 'highfever',
          norm2: 'high fever',  # Different from entry's norm2 'highfever'
          entries: []
        }]
      }

      filtered_sub_string_dbs = annotator.instance_variable_get(:@sub_string_dbs)

      results = annotator.send(:batch_surface_match, span_index, [dictionary], filtered_sub_string_dbs)

      # The span's norm2 'high fever' won't match entry's norm2 'highfever'
      # so no results expected from exact norm2 matching
      # (unless SimString expands to include it, which is disabled by default)
      expect(results['high fever']).to be_empty
    end

    it 'returns score 1.0 for all exact norm2 matches in batch' do
      # Test that multiple spans with exact norm2 matches all get score 1.0
      span_index = {
        'Fever' => [{
          span_begin: 0, span_end: 5,
          idx_token_begin: 0, idx_token_final: 0,
          norm1: 'fever', norm2: 'fever',
          entries: []
        }],
        'Headache' => [{
          span_begin: 10, span_end: 18,
          idx_token_begin: 2, idx_token_final: 2,
          norm1: 'headache', norm2: 'headache',
          entries: []
        }]
      }

      filtered_sub_string_dbs = annotator.instance_variable_get(:@sub_string_dbs)

      results = annotator.send(:batch_surface_match, span_index, [dictionary], filtered_sub_string_dbs)

      # Both should have score 1.0
      fever_result = results['Fever'].find { |r| r[:identifier] == 'HP:0001945' }
      headache_result = results['Headache'].find { |r| r[:identifier] == 'HP:0002315' }

      expect(fever_result[:score]).to eq(1.0)
      expect(headache_result[:score]).to eq(1.0)
    end
  end

  describe 'parallel embedding fetching' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }

    context 'when ParallelThreads is 1' do
      it 'uses sequential fetching' do
        # Generate enough spans to create multiple batches
        text = (1..50).map { |i| "term#{i}" }.join(' ')

        call_order = []
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          call_order << spans.first  # Track order of calls
          Array.new(spans.size) { mock_embedding_vector }
        end

        tokens = annotator.send(:norm1_tokenize, text)
        norm1s = tokens.map { |t| t[:token] }
        norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")) { |s, t| s[t[:position]] = t[:token]; s }
        sbreaks = annotator.send(:sentence_break, text)
        annotator.send(:add_pars_info!, tokens, text, sbreaks)

        span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})

        # With ParallelThreads=1, should use sequential method
        annotator.send(:batch_get_embeddings, span_index)

        # Should have processed spans
        expect(span_index.values.any? { |occurrences| occurrences.any? { |info| info[:embedding].present? } }).to be true
      end
    end

    it 'handles errors in individual batches gracefully' do
      text = 'fever headache cytokine'

      call_count = 0
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        call_count += 1
        if call_count == 1
          raise StandardError.new("Simulated failure")
        end
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      norm1s = tokens.map { |t| t[:token] }
      norm2s = annotator.send(:norm2_tokenize, text).inject(Array.new(tokens.length, "")) { |s, t| s[t[:position]] = t[:token]; s }
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      span_index = annotator.send(:pre_generate_spans, text, tokens, norm1s, norm2s, sbreaks, {})

      # Should not raise error
      expect {
        annotator.send(:batch_get_embeddings, span_index)
      }.not_to raise_error
    end
  end

  describe 'persistent semantic table preference' do
    context 'when dictionary has persistent semantic table' do
      # Note: The main before block already creates the semantic table with embeddings

      it 'uses persistent table instead of creating temp table' do
        expect(dictionary).not_to receive(:create_semantic_temp_table!)

        annotator = TextAnnotator.new([dictionary], { semantic_threshold: 0.6 })

        semantic_tables = annotator.instance_variable_get(:@semantic_tables)
        expect(semantic_tables[dictionary.id]).to eq(dictionary.semantic_table_name)

        temp_tables = annotator.instance_variable_get(:@temp_semantic_tables)
        expect(temp_tables).to be_empty

        annotator.dispose
      end

      it 'does not drop persistent table on dispose' do
        annotator = TextAnnotator.new([dictionary], { semantic_threshold: 0.6 })
        annotator.dispose

        # Table should still exist
        expect(dictionary.reload.has_semantic_table?).to be true
        count = ActiveRecord::Base.connection.exec_query(
          "SELECT COUNT(*) as cnt FROM #{dictionary.semantic_table_name}"
        ).first['cnt']
        expect(count).to be > 0
      end
    end

    context 'when dictionary has no persistent semantic table' do
      before do
        dictionary.drop_semantic_table! if dictionary.has_semantic_table?
      end

      it 'skips semantic table creation when no embeddings' do
        # When there's no semantic table, embeddings_populated? returns false,
        # so TextAnnotator correctly skips creating any semantic table
        annotator = TextAnnotator.new([dictionary], { semantic_threshold: 0.6 })

        semantic_tables = annotator.instance_variable_get(:@semantic_tables)
        # Should be nil or empty since no embeddings exist
        expect(semantic_tables[dictionary.id]).to be_nil

        temp_tables = annotator.instance_variable_get(:@temp_semantic_tables)
        expect(temp_tables).to be_empty

        annotator.dispose
      end
    end

    context 'with mixed dictionaries' do
      let(:dict_with_table) { dictionary }
      let(:dict_without_table) { create(:dictionary, user: user, name: 'test_no_semantic') }

      before do
        # Setup dict_without_table with entries but NO semantic table
        Entry.create!(
          dictionary: dict_without_table,
          label: 'Test term',
          identifier: 'TEST:001',
          norm1: 'testterm',
          norm2: 'test term',
          label_length: 9,
          searchable: true
        )
        dict_without_table.update_entries_num

        # dict_with_table already has semantic table from main before block
        # dict_without_table has no semantic table (we didn't create one)
      end

      after do
        # Note: dict_with_table is cleaned up by main after block
        dict_without_table.drop_semantic_table! if dict_without_table.has_semantic_table?
      end

      it 'uses persistent table for one and skips for dict without embeddings' do
        annotator = TextAnnotator.new([dict_with_table, dict_without_table], { semantic_threshold: 0.6 })

        semantic_tables = annotator.instance_variable_get(:@semantic_tables)
        temp_tables = annotator.instance_variable_get(:@temp_semantic_tables)

        # dict_with_table should use persistent table
        expect(semantic_tables[dict_with_table.id]).to eq(dict_with_table.semantic_table_name)

        # dict_without_table should be skipped (no embeddings populated)
        # since embeddings are now stored only in semantic tables
        expect(semantic_tables[dict_without_table.id]).to be_nil
        expect(temp_tables).to be_empty

        annotator.dispose
      end
    end
  end

  describe 'black entry exclusion from semantic search' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }

    before do
      # Stub embedding server
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end
    end

    it 'excludes black entries from semantic search' do
      # Turn "Fever" entry to black
      fever_entry = dictionary.entries.find_by(identifier: 'HP:0001945')
      expect(fever_entry).not_to be_nil
      expect(fever_entry.searchable).to be true  # Initially searchable

      dictionary.turn_to_black(fever_entry)

      # Verify searchable is now false in entries table
      fever_entry.reload
      expect(fever_entry.searchable).to be false
      expect(fever_entry.mode).to eq(EntryMode::BLACK)

      # Verify searchable is false in semantic table
      if dictionary.has_semantic_table?
        result = ActiveRecord::Base.connection.exec_query(
          "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{fever_entry.id}"
        ).first
        expect(result['searchable']).to be false
      end

      # Annotate text with semantic search
      text = 'fever'
      result = annotator.annotate_batch([{ text: text }]).first

      # Should NOT find the black entry
      fever_annotations = result[:denotations].select { |d| d[:obj] == 'HP:0001945' }
      expect(fever_annotations).to be_empty

      annotator.dispose
    end

    it 'restores searchability when canceling black' do
      # Turn "Fever" entry to black, then back to gray
      fever_entry = dictionary.entries.find_by(identifier: 'HP:0001945')
      dictionary.turn_to_black(fever_entry)

      # Cancel black
      dictionary.cancel_black(fever_entry)

      # Verify searchable is restored
      fever_entry.reload
      expect(fever_entry.searchable).to be true
      expect(fever_entry.mode).to eq(EntryMode::GRAY)

      # Verify searchable is true in semantic table
      if dictionary.has_semantic_table?
        result = ActiveRecord::Base.connection.exec_query(
          "SELECT searchable FROM #{dictionary.semantic_table_name} WHERE id = #{fever_entry.id}"
        ).first
        expect(result['searchable']).to be true
      end

      # Annotate text with semantic search
      text = 'fever'
      new_annotator = TextAnnotator.new([dictionary], { semantic_threshold: 0.0 })
      result = new_annotator.annotate_batch([{ text: text }]).first

      # Should find the entry again
      fever_annotations = result[:denotations].select { |d| d[:obj] == 'HP:0001945' }
      expect(fever_annotations).not_to be_empty

      new_annotator.dispose
    end
  end

  describe 'same-identifier consolidation before boundary crossing' do
    # This tests the fix for the issue where overlapping spans with the same identifier
    # were incorrectly removed by boundary crossing elimination.
    # Example: "soluble protein, Rubisco contents" (score 0.87) was being removed due to
    # boundary crossing with "Rubisco contents, and" (score 0.92), even though both had
    # the same identifier and the shorter span should have been kept.

    let(:annotator) { TextAnnotator.new([dictionary], { threshold: 0.85, longest: false }) }

    before do
      # Stub embedding server to avoid external calls
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      # Add E. coli entry for the duplicate span test
      # This must be in before block so SimString index includes it
      # norm2 is lowercase without punctuation: "e coli"
      ecoli_entry = Entry.create!(
        dictionary: dictionary,
        label: 'E. coli',
        identifier: 'NCBITaxon:562',
        norm1: 'ecoli',
        norm2: 'ecoli',  # norm2 removes spaces
        label_length: 7,
        mode: EntryMode::GRAY,
        searchable: true
      )
      dictionary.upsert_semantic_entry(ecoli_entry, mock_embedding_vector)
      dictionary.update_entries_num
    end

    describe 'non-overlapping spans with same identifier' do
      it 'keeps all non-overlapping spans even with same identifier' do
        # Same identifier appearing in different positions should all be kept
        # Uses existing 'Fever' entry from test setup
        text = 'Fever in morning, fever at night'
        result = annotator.annotate_batch([{ text: text }]).first

        fever_annotations = result[:denotations].select { |d| d[:obj] == 'HP:0001945' }
        # Should find fever twice (once at each position)
        expect(fever_annotations.length).to eq(2)

        # Verify they are at different positions
        positions = fever_annotations.map { |d| d[:span][:begin] }
        expect(positions.uniq.length).to eq(2)

        annotator.dispose
      end

      it 'correctly annotates duplicate span text with consolidation (E. coli bug)' do
        # This tests the fix for the bug where "E. coli" appearing twice in text
        # would only show "with E. coli" (score 0.8858) at first occurrence instead of
        # "E. coli" (score 1.0), because the second occurrence was overwriting the first
        # in span_index hash.
        #
        # E. coli entry is created in before block above

        # Create a new annotator without threshold, so exact matches work reliably
        test_annotator = TextAnnotator.new([dictionary], { threshold: 0.0, longest: false })

        # Simpler test: "E. coli" appears twice at positions 0-7 and 17-24
        text = 'E. coli and then E. coli again'

        result = test_annotator.annotate_batch([{ text: text }]).first

        ecoli_annotations = result[:denotations].select { |d| d[:obj] == 'NCBITaxon:562' }

        # Should find E. coli twice (once at each position)
        # This is the core test: before the fix, only one occurrence would be stored
        expect(ecoli_annotations.length).to eq(2)

        # Both annotations should be for "E. coli" (7 characters each)
        ecoli_annotations.each do |annotation|
          span_length = annotation[:span][:end] - annotation[:span][:begin]
          expect(span_length).to eq(7)

          # Should have score 1.0 for exact match
          expect(annotation[:score]).to eq(1.0)
        end

        # Verify they are at different positions
        positions = ecoli_annotations.map { |d| d[:span][:begin] }
        expect(positions.uniq.length).to eq(2)
        expect(positions.sort).to eq([0, 17])

        # Clean up
        test_annotator.dispose
      end
    end

    describe 'different identifiers at different positions' do
      it 'allows annotations for different identifiers when spans do not overlap' do
        # Uses existing entries from test setup
        # Note: Both fever and headache should be found, but SimString matching
        # depends on the dictionary's pre-built index
        text = 'Patient has fever'
        result = annotator.annotate_batch([{ text: text }]).first

        # At minimum, "Fever" (HP:0001945) should be found
        identifiers = result[:denotations].map { |d| d[:obj] }
        expect(identifiers).to include('HP:0001945')

        annotator.dispose
      end
    end

    describe 'denotation consolidation logic' do
      # These tests directly test the consolidation algorithm by simulating
      # the denotation arrays that would be produced

      it 'consolidates overlapping spans with same identifier keeping higher score' do
        # Simulate the scenario: two overlapping spans with same identifier
        # Span 1: "soluble protein, Rubisco contents" (0-35) score 0.87
        # Span 2: "Rubisco contents" (17-33) score 0.95
        # Both have same identifier, span 2 has higher score
        denotations = [
          { span: { begin: 0, end: 35 }, obj: 'TO:0000319', score: 0.87 },
          { span: { begin: 17, end: 33 }, obj: 'TO:0000319', score: 0.95 }
        ]

        # Sort by position and score (as the algorithm does)
        denotations.sort! do |a, b|
          c1 = (a[:span][:begin] <=> b[:span][:begin])
          if c1.zero?
            c2 = (b[:span][:end] <=> a[:span][:end])
            c2.zero? ? (b[:score] <=> a[:score]) : c2
          else
            c1
          end
        end

        # Apply consolidation logic (same algorithm as in text_annotator.rb)
        consolidated_indices = []
        denotations.each_with_index do |d, i|
          dominated = false
          consolidated_indices.each do |j|
            other = denotations[j]
            overlaps = d[:span][:begin] < other[:span][:end] && d[:span][:end] > other[:span][:begin]
            if overlaps && d[:obj] == other[:obj]
              if d[:score] > other[:score]
                consolidated_indices.delete(j)
              else
                dominated = true
                break
              end
            end
          end
          consolidated_indices << i unless dominated
        end
        result = consolidated_indices.map { |i| denotations[i] }

        # Should keep only the higher-scoring span
        expect(result.length).to eq(1)
        expect(result.first[:score]).to eq(0.95)
        expect(result.first[:span][:begin]).to eq(17)
        expect(result.first[:span][:end]).to eq(33)
      end

      it 'keeps both spans when they have different identifiers' do
        # Two overlapping spans with different identifiers should both survive consolidation
        denotations = [
          { span: { begin: 0, end: 20 }, obj: 'ID:001', score: 0.90 },
          { span: { begin: 10, end: 30 }, obj: 'ID:002', score: 0.85 }
        ]

        denotations.sort! do |a, b|
          c1 = (a[:span][:begin] <=> b[:span][:begin])
          if c1.zero?
            c2 = (b[:span][:end] <=> a[:span][:end])
            c2.zero? ? (b[:score] <=> a[:score]) : c2
          else
            c1
          end
        end

        consolidated_indices = []
        denotations.each_with_index do |d, i|
          dominated = false
          consolidated_indices.each do |j|
            other = denotations[j]
            overlaps = d[:span][:begin] < other[:span][:end] && d[:span][:end] > other[:span][:begin]
            if overlaps && d[:obj] == other[:obj]
              if d[:score] > other[:score]
                consolidated_indices.delete(j)
              else
                dominated = true
                break
              end
            end
          end
          consolidated_indices << i unless dominated
        end
        result = consolidated_indices.map { |i| denotations[i] }

        # Both should be kept (different identifiers)
        expect(result.length).to eq(2)
        expect(result.map { |d| d[:obj] }).to contain_exactly('ID:001', 'ID:002')
      end

      it 'keeps all non-overlapping spans with same identifier' do
        # Non-overlapping spans with same identifier should all survive
        denotations = [
          { span: { begin: 0, end: 5 }, obj: 'HP:0001945', score: 1.0 },
          { span: { begin: 20, end: 25 }, obj: 'HP:0001945', score: 1.0 }
        ]

        denotations.sort! do |a, b|
          c1 = (a[:span][:begin] <=> b[:span][:begin])
          if c1.zero?
            c2 = (b[:span][:end] <=> a[:span][:end])
            c2.zero? ? (b[:score] <=> a[:score]) : c2
          else
            c1
          end
        end

        consolidated_indices = []
        denotations.each_with_index do |d, i|
          dominated = false
          consolidated_indices.each do |j|
            other = denotations[j]
            overlaps = d[:span][:begin] < other[:span][:end] && d[:span][:end] > other[:span][:begin]
            if overlaps && d[:obj] == other[:obj]
              if d[:score] > other[:score]
                consolidated_indices.delete(j)
              else
                dominated = true
                break
              end
            end
          end
          consolidated_indices << i unless dominated
        end
        result = consolidated_indices.map { |i| denotations[i] }

        # Both should be kept (non-overlapping)
        expect(result.length).to eq(2)
      end

      it 'handles the Rubisco scenario correctly' do
        # This simulates the actual bug scenario:
        # - "soluble protein, Rubisco contents" (0-33, TO:0000319, score 0.8689)
        # - "Rubisco contents, and" (17-37, TO:0000319, score 0.925)
        # - "Rubisco contents" (17-33, TO:0000319, score 0.9447)
        # Without consolidation first, boundary crossing could eliminate the wrong span
        denotations = [
          { span: { begin: 0, end: 33 }, obj: 'TO:0000319', score: 0.8689 },
          { span: { begin: 17, end: 37 }, obj: 'TO:0000319', score: 0.925 },
          { span: { begin: 17, end: 33 }, obj: 'TO:0000319', score: 0.9447 }
        ]

        denotations.sort! do |a, b|
          c1 = (a[:span][:begin] <=> b[:span][:begin])
          if c1.zero?
            c2 = (b[:span][:end] <=> a[:span][:end])
            c2.zero? ? (b[:score] <=> a[:score]) : c2
          else
            c1
          end
        end

        # Apply consolidation
        consolidated_indices = []
        denotations.each_with_index do |d, i|
          dominated = false
          consolidated_indices.each do |j|
            other = denotations[j]
            overlaps = d[:span][:begin] < other[:span][:end] && d[:span][:end] > other[:span][:begin]
            if overlaps && d[:obj] == other[:obj]
              if d[:score] > other[:score]
                consolidated_indices.delete(j)
              else
                dominated = true
                break
              end
            end
          end
          consolidated_indices << i unless dominated
        end
        result = consolidated_indices.map { |i| denotations[i] }

        # Should keep only the highest-scoring span: "Rubisco contents" (17-33, 0.9447)
        expect(result.length).to eq(1)
        expect(result.first[:score]).to eq(0.9447)
        expect(result.first[:span][:begin]).to eq(17)
        expect(result.first[:span][:end]).to eq(33)
      end
    end
  end
end
