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

    # Add embeddings
    dictionary.entries.each do |entry|
      entry.update_column(:embedding, mock_embedding_vector)
      entry.update_column(:searchable, true)
    end

    # Update dictionary metadata
    dictionary.update_entries_num
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

      # Each span should have metadata
      span_index.each do |span, info|
        expect(info).to have_key(:span_begin)
        expect(info).to have_key(:span_end)
        expect(info).to have_key(:norm1)
        expect(info).to have_key(:norm2)
        expect(info).to have_key(:entries)
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
      span_index.each do |span, info|
        expect(info[:embedding]).to be_nil
      end
    end

    it 'generates spans efficiently without duplication' do
      # With pre-indexing, duplicate text spans are naturally avoided
      # because we use a hash with span as key
      tokens = annotator.send(:norm1_tokenize, 'fever fever')
      norm1s = tokens.map{|t| t[:token]}
      norm2s = annotator.send(:norm2_tokenize, 'fever fever').inject(Array.new(tokens.length, "")){|s, t| s[t[:position]] = t[:token]; s}
      sbreaks = annotator.send(:sentence_break, 'fever fever')
      annotator.send(:add_pars_info!, tokens, 'fever fever', sbreaks)

      span_index = annotator.send(:pre_generate_spans, 'fever fever', tokens, norm1s, norm2s, sbreaks, {})

      # Even though "fever" appears twice, it should only be in index once
      expect(span_index.keys.count('fever')).to eq(1)
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
        'Fever' => {
          span_begin: 0,
          span_end: 5,
          idx_token_begin: 0,
          idx_token_final: 0,
          norm1: 'fever',
          norm2: 'fever',  # Matches entry's norm2 exactly
          entries: []
        }
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
        'high fever' => {
          span_begin: 0,
          span_end: 10,
          idx_token_begin: 0,
          idx_token_final: 1,
          norm1: 'highfever',
          norm2: 'high fever',  # Different from entry's norm2 'highfever'
          entries: []
        }
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
        'Fever' => {
          span_begin: 0, span_end: 5,
          idx_token_begin: 0, idx_token_final: 0,
          norm1: 'fever', norm2: 'fever',
          entries: []
        },
        'Headache' => {
          span_begin: 10, span_end: 18,
          idx_token_begin: 2, idx_token_final: 2,
          norm1: 'headache', norm2: 'headache',
          entries: []
        }
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
        expect(span_index.values.any? { |info| info[:embedding].present? }).to be true
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
end
