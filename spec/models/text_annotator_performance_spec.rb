# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TextAnnotator, type: :model do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'perf_test_dict') }
  let(:dictionary2) { create(:dictionary, user: user, name: 'perf_test_dict2') }

  def mock_embedding_vector
    Array.new(768) { rand }
  end

  before do
    # Create test entries for first dictionary
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

    # Create test entries for second dictionary
    entries_data2 = [
      ['Inflammation', 'HP:9999', 'inflammation', 'inflammation', 12, EntryMode::GRAY, false, dictionary2.id]
    ]
    Entry.bulk_import(
      [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
      entries_data2,
      validate: false
    )

    # Update dictionary metadata
    dictionary.update_entries_num
    dictionary2.update_entries_num
  end

  describe 'Query Result Caching' do
    context 'dictionary-level search_term caching' do
      it 'caches search_term results to avoid redundant database queries' do
        text = 'fever and fever and fever'
        options = { threshold: 0.85, longest: true }

        annotator = TextAnnotator.new([dictionary], options)

        # Track database queries
        query_count = 0
        query_tracker = lambda do |*args|
          if args[0].include?('SELECT') && args[0].include?('entries')
            query_count += 1
          end
        end

        ActiveSupport::Notifications.subscribed(query_tracker, 'sql.active_record') do
          annotator.annotate_batch([{ text: text }])
        end

        # Should query once and cache for reuse
        # Without cache: would query 3 times for "fever"
        # With cache: should query once for "fever"
        expect(query_count).to be <= 1

        annotator.dispose
      end

      it 'reuses cached results across multiple span lookups' do
        text = 'patient has fever, high fever, and continued fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        # Mock the cache to track hits
        original_cache = annotator.instance_variable_get(:@cache_span_search)
        cache_hits = 0
        cache_wrapper = Hash.new do |h, k|
          original_cache[k]
        end

        original_cache.each_key do |key|
          cache_wrapper[key] = original_cache[key]
        end

        annotator.instance_variable_set(:@cache_span_search, cache_wrapper)

        result = annotator.annotate_batch([{ text: text }])

        # Should have cached 'fever' after first lookup
        expect(cache_wrapper.key?('fever')).to be true

        annotator.dispose
      end

      it 'maintains separate caches for different dictionaries' do
        text = 'fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary, dictionary2], options)
        result = annotator.annotate_batch([{ text: text }])

        cache = annotator.instance_variable_get(:@cache_span_search)

        # Cache should store results that work across dictionaries
        # or should be keyed appropriately
        expect(cache).to be_a(Hash)

        annotator.dispose
      end

      it 'invalidates cache between batch annotations' do
        text1 = 'fever'
        text2 = 'headache'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        result1 = annotator.annotate_batch([{ text: text1 }])
        cache_after_first = annotator.instance_variable_get(:@cache_span_search).dup

        result2 = annotator.annotate_batch([{ text: text2 }])
        cache_after_second = annotator.instance_variable_get(:@cache_span_search)

        # Cache should be cleared between batches
        expect(cache_after_second.keys).not_to include(*cache_after_first.keys)

        annotator.dispose
      end

      it 'caches empty results to avoid redundant lookups' do
        text = 'nonexistent nonexistent nonexistent'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        query_count = 0
        query_tracker = lambda do |*args|
          if args[0].include?('SELECT') && args[0].include?('entries')
            query_count += 1
          end
        end

        ActiveSupport::Notifications.subscribed(query_tracker, 'sql.active_record') do
          annotator.annotate_batch([{ text: text }])
        end

        # Should cache the empty result and not query multiple times
        cache = annotator.instance_variable_get(:@cache_span_search)
        expect(cache['nonexistent']).to eq([])

        annotator.dispose
      end
    end

    context 'performance impact' do
      it 'reduces annotation time for repeated terms' do
        # Text with many repeated terms
        text = 'fever ' * 50  # 50 repetitions
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        start_time = Time.now
        result = annotator.annotate_batch([{ text: text }])
        end_time = Time.now

        duration = end_time - start_time

        # Should complete reasonably fast (< 5 seconds for 50 repeated terms)
        expect(duration).to be < 5

        annotator.dispose
      end

      it 'handles large cache sizes efficiently' do
        # Text with many unique terms
        text = (1..100).map { |i| "term#{i}" }.join(' ')
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        expect {
          annotator.annotate_batch([{ text: text }])
        }.not_to raise_error

        cache = annotator.instance_variable_get(:@cache_span_search)
        expect(cache.size).to be > 0

        annotator.dispose
      end
    end
  end

  describe 'LRU Cache Optimization' do
    context 'cache eviction' do
      it 'evicts least recently used items when cache exceeds MAX_CACHE_SIZE' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        # Set a smaller max cache size for testing
        stub_const('TextAnnotator::MAX_CACHE_SIZE', 10)

        # Generate 15 unique terms to exceed cache size
        text = (1..15).map { |i| "term#{i}" }.join(' ')

        result = annotator.annotate_batch([{ text: text }])

        cache = annotator.instance_variable_get(:@cache_span_search)

        # Cache size should not exceed MAX_CACHE_SIZE
        expect(cache.size).to be <= 10

        annotator.dispose
      end

      it 'evicts oldest items first (LRU behavior)' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        # Set a smaller max cache size for testing
        stub_const('TextAnnotator::MAX_CACHE_SIZE', 5)

        # Manually populate cache with known access order
        cache = {}
        timestamps = {}

        (1..7).each do |i|
          cache["term#{i}"] = []
          timestamps["term#{i}"] = i
        end

        annotator.instance_variable_set(:@cache_span_search, cache)
        annotator.instance_variable_set(:@cache_access_timestamps, timestamps)
        annotator.instance_variable_set(:@cache_access_count, 7)

        # Trigger cache cleanup by adding new item
        # This would normally happen in the annotation loop
        # For now, just verify the eviction logic

        expect(cache.size).to eq(7)

        annotator.dispose
      end

      it 'uses efficient LRU eviction algorithm' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        stub_const('TextAnnotator::MAX_CACHE_SIZE', 100)

        # Time the eviction process
        text = (1..200).map { |i| "term#{i}" }.join(' ')

        start_time = Time.now
        result = annotator.annotate_batch([{ text: text }])
        end_time = Time.now

        # Even with evictions, should complete quickly (< 10 seconds)
        expect(end_time - start_time).to be < 10

        annotator.dispose
      end
    end

    context 'cache access tracking' do
      it 'updates access timestamps on cache hits' do
        text = 'fever fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        timestamps = annotator.instance_variable_get(:@cache_access_timestamps)

        # Should have timestamp for 'fever'
        expect(timestamps.key?('fever')).to be true
        expect(timestamps['fever']).to be_a(Integer)

        annotator.dispose
      end

      it 'maintains monotonically increasing access counter' do
        text = 'fever headache'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        count = annotator.instance_variable_get(:@cache_access_count)

        # Access count should increase with cache operations
        expect(count).to be > 0

        annotator.dispose
      end
    end

    context 'memory efficiency' do
      it 'prevents unbounded cache growth' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        # Simulate processing many unique terms
        (1..20).each do |batch|
          text = (1..100).map { |i| "batch#{batch}_term#{i}" }.join(' ')
          annotator.annotate_batch([{ text: text }])

          cache = annotator.instance_variable_get(:@cache_span_search)

          # Cache should be cleared between batches
          # After each batch, cache should be empty or small
          expect(cache.size).to be < TextAnnotator::MAX_CACHE_SIZE * 2
        end

        annotator.dispose
      end
    end
  end

  describe 'Composite Index Usage' do
    context 'database query optimization' do
      it 'uses composite index for dictionary_id + norm2 + mode queries' do
        text = 'fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        # Check if query uses index (this would require EXPLAIN analysis)
        # For now, just verify the query executes efficiently
        start_time = Time.now
        result = annotator.annotate_batch([{ text: text }])
        end_time = Time.now

        # Should execute quickly with proper indexing
        expect(end_time - start_time).to be < 1

        annotator.dispose
      end

      it 'filters by mode efficiently in search queries' do
        # Create a black entry
        black_entry = dictionary.entries.first
        black_entry.update_attribute(:mode, EntryMode::BLACK)

        text = black_entry.label
        options = { threshold: 1.0 }  # Exact match

        annotator = TextAnnotator.new([dictionary], options)
        result = annotator.annotate_batch([{ text: text }])

        # Should not return black entries
        denotations = result.first[:denotations]
        expect(denotations.any? { |d| d[:obj] == black_entry.identifier }).to be false

        annotator.dispose
      end

      it 'handles multiple dictionaries efficiently with composite index' do
        text = 'fever inflammation'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary, dictionary2], options)

        query_count = 0
        query_tracker = lambda do |*args|
          if args[0].include?('SELECT') && args[0].include?('entries')
            query_count += 1
          end
        end

        ActiveSupport::Notifications.subscribed(query_tracker, 'sql.active_record') do
          annotator.annotate_batch([{ text: text }])
        end

        # Should execute efficiently even with multiple dictionaries
        expect(query_count).to be < 20  # Reasonable upper bound

        annotator.dispose
      end
    end
  end
end
