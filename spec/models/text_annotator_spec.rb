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

    it 'initializes embedding cache' do
      annotator = TextAnnotator.new([dictionary], {})

      cache = annotator.instance_variable_get(:@cache_embeddings)
      expect(cache).to be_a(Hash)
      expect(cache).to be_empty
    end
  end

  describe '#collect_and_cache_embeddings' do
    let(:annotator) { TextAnnotator.new([dictionary], { semantic_threshold: 0.6 }) }
    let(:text) { 'cytokine release syndrome' }

    it 'collects all possible spans from text' do
      # Mock embedding server
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      annotator.send(:collect_and_cache_embeddings, text, tokens, sbreaks)

      cache = annotator.instance_variable_get(:@cache_embeddings)

      # Should cache embeddings for: "cytokine", "release", "syndrome",
      # "cytokine release", "release syndrome", "cytokine release syndrome"
      expect(cache.keys).to include('cytokine', 'release', 'syndrome')
      expect(cache.keys.size).to be >= 3
    end

    it 'batch generates embeddings in single API call' do
      expect(EmbeddingServer).to receive(:fetch_embeddings).once do |spans|
        expect(spans).to be_an(Array)
        expect(spans.size).to be > 0
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      annotator.send(:collect_and_cache_embeddings, text, tokens, sbreaks)
    end

    it 'does not cache duplicate spans' do
      allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        # Verify all spans are unique
        expect(spans.uniq.size).to eq(spans.size)
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      annotator.send(:collect_and_cache_embeddings, text, tokens, sbreaks)
    end

    it 'handles embedding server failures gracefully' do
      allow(EmbeddingServer).to receive(:fetch_embeddings).and_raise(StandardError.new("Server error"))

      tokens = annotator.send(:norm1_tokenize, text)
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      # Should not raise error, just log and continue
      expect {
        annotator.send(:collect_and_cache_embeddings, text, tokens, sbreaks)
      }.not_to raise_error

      cache = annotator.instance_variable_get(:@cache_embeddings)
      expect(cache).to be_empty
    end

    it 'skips already cached spans' do
      # Pre-populate cache
      existing_cache = { 'cytokine' => mock_embedding_vector }
      annotator.instance_variable_set(:@cache_embeddings, existing_cache)

      # Should only fetch non-cached spans
      expect(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
        expect(spans).not_to include('cytokine')
        Array.new(spans.size) { mock_embedding_vector }
      end

      tokens = annotator.send(:norm1_tokenize, text)
      sbreaks = annotator.send(:sentence_break, text)
      annotator.send(:add_pars_info!, tokens, text, sbreaks)

      annotator.send(:collect_and_cache_embeddings, text, tokens, sbreaks)
    end
  end

  describe '#annotate_batch with semantic search' do
    context 'performance optimization' do
      it 'batch generates embeddings before annotation loop' do
        text = 'cytokine release syndrome is a serious condition'
        options = { semantic_threshold: 0.6, longest: true }

        # Expect single batch call for all spans
        expect(EmbeddingServer).to receive(:fetch_embeddings).once do |spans|
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

        expect(EmbeddingServer).not_to receive(:fetch_embeddings)

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        annotator.dispose
      end
    end

    context 'cache usage during annotation' do
      it 'uses cached embeddings for semantic search' do
        text = 'fever and headache'
        options = { semantic_threshold: 0.6, longest: true }

        call_count = 0
        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          call_count += 1
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        # Should only call once (batch generation), not for each span search
        expect(call_count).to eq(1)

        annotator.dispose
      end

      it 'reuses embeddings across multiple dictionaries' do
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

        # Should still only call once, cache reused for both dictionaries
        expect(call_count).to eq(1)

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

    context 'span search cache integration' do
      it 'caches search results including semantic results' do
        text = 'fever and fever'
        options = { semantic_threshold: 0.6, longest: true }

        allow(EmbeddingServer).to receive(:fetch_embeddings) do |spans|
          Array.new(spans.size) { mock_embedding_vector }
        end

        annotator = TextAnnotator.new([dictionary], options)

        # First annotation
        result1 = annotator.annotate_batch([{ text: text }]).first

        # Get span cache
        span_cache = annotator.instance_variable_get(:@cache_span_search)
        expect(span_cache['fever']).not_to be_nil

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
end
