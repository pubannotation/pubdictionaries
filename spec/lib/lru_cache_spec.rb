# frozen_string_literal: true

require 'rails_helper'
require_relative '../../app/lib/lru_cache'

RSpec.describe LruCache do
  describe 'Basic Operations' do
    let(:cache) { LruCache.new(3) }

    it 'stores and retrieves values' do
      cache.put('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')
    end

    it 'returns nil for non-existent keys' do
      expect(cache.get('nonexistent')).to be_nil
    end

    it 'updates existing keys' do
      cache.put('key1', 'value1')
      cache.put('key1', 'value2')
      expect(cache.get('key1')).to eq('value2')
      expect(cache.size).to eq(1)
    end

    it 'checks key existence' do
      cache.put('key1', 'value1')
      expect(cache.key?('key1')).to be true
      expect(cache.key?('key2')).to be false
    end

    it 'tracks cache size' do
      expect(cache.size).to eq(0)
      cache.put('key1', 'value1')
      expect(cache.size).to eq(1)
      cache.put('key2', 'value2')
      expect(cache.size).to eq(2)
    end

    it 'clears all entries' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.clear
      expect(cache.size).to eq(0)
      expect(cache.empty?).to be true
    end

    it 'returns all keys' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      expect(cache.keys).to contain_exactly('key1', 'key2')
    end
  end

  describe 'LRU Eviction' do
    let(:cache) { LruCache.new(3) }

    it 'evicts least recently used item when capacity exceeded' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')
      cache.put('key4', 'value4')  # This should evict key1

      expect(cache.size).to eq(3)
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to eq('value2')
      expect(cache.get('key3')).to eq('value3')
      expect(cache.get('key4')).to eq('value4')
    end

    it 'updates LRU order on get' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')

      # Access key1 to make it most recently used
      cache.get('key1')

      # Add key4, should evict key2 (least recently used)
      cache.put('key4', 'value4')

      expect(cache.get('key1')).to eq('value1')  # Still present
      expect(cache.get('key2')).to be_nil        # Evicted
      expect(cache.get('key3')).to eq('value3')
      expect(cache.get('key4')).to eq('value4')
    end

    it 'updates LRU order on put' do
      cache.put('key1', 'value1')
      cache.put('key2', 'value2')
      cache.put('key3', 'value3')

      # Update key1 to make it most recently used
      cache.put('key1', 'updated_value1')

      # Add key4, should evict key2
      cache.put('key4', 'value4')

      expect(cache.get('key1')).to eq('updated_value1')
      expect(cache.get('key2')).to be_nil
      expect(cache.get('key3')).to eq('value3')
      expect(cache.get('key4')).to eq('value4')
    end

    it 'maintains correct order with multiple accesses' do
      cache.put('a', 1)
      cache.put('b', 2)
      cache.put('c', 3)

      # Access pattern: b, a, c, b, a
      cache.get('b')  # b is most recent
      cache.get('a')  # a is most recent
      cache.get('c')  # c is most recent
      cache.get('b')  # b is most recent
      cache.get('a')  # a is most recent

      # Now order is: a (most recent), b, c (least recent)
      cache.put('d', 4)  # Should evict c

      expect(cache.get('a')).to eq(1)
      expect(cache.get('b')).to eq(2)
      expect(cache.get('c')).to be_nil
      expect(cache.get('d')).to eq(4)
    end
  end

  describe 'Fetch with Block' do
    let(:cache) { LruCache.new(3) }

    it 'returns cached value if exists' do
      cache.put('key1', 'cached_value')

      result = cache.fetch('key1') { 'computed_value' }

      expect(result).to eq('cached_value')
    end

    it 'computes and caches value if not exists' do
      result = cache.fetch('key1') { 'computed_value' }

      expect(result).to eq('computed_value')
      expect(cache.get('key1')).to eq('computed_value')
    end

    it 'returns nil for missing key without block' do
      result = cache.fetch('nonexistent')
      expect(result).to be_nil
    end

    it 'only computes once for same key' do
      call_count = 0
      computation = -> do
        call_count += 1
        "computed_#{call_count}"
      end

      result1 = cache.fetch('key1', &computation)
      result2 = cache.fetch('key1', &computation)

      expect(result1).to eq('computed_1')
      expect(result2).to eq('computed_1')
      expect(call_count).to eq(1)
    end
  end

  describe 'Thread Safety' do
    let(:cache) { LruCache.new(100) }

    it 'handles concurrent reads and writes' do
      threads = []
      10.times do |i|
        threads << Thread.new do
          10.times do |j|
            cache.put("key_#{i}_#{j}", "value_#{i}_#{j}")
            cache.get("key_#{i}_#{j}")
          end
        end
      end

      threads.each(&:join)

      # Should not raise any errors
      expect(cache.size).to be <= 100
      expect(cache.size).to be > 0
    end

    it 'maintains consistency under concurrent access' do
      threads = []
      results = []

      # Multiple threads incrementing a counter
      threads = 100.times.map do |i|
        Thread.new do
          cache.put('counter', i)
        end
      end

      threads.each(&:join)

      # Final value should be between 0 and 99
      final_value = cache.get('counter')
      expect(final_value).to be_between(0, 99)
    end

    it 'prevents race conditions in eviction' do
      small_cache = LruCache.new(10)
      threads = []

      20.times do |i|
        threads << Thread.new do
          100.times do |j|
            small_cache.put("key_#{i}_#{j}", "value")
          end
        end
      end

      threads.each(&:join)

      # Cache size should not exceed capacity
      expect(small_cache.size).to be <= 10
    end
  end

  describe 'Performance' do
    it 'provides O(1) get operation' do
      large_cache = LruCache.new(10_000)

      # Fill cache
      10_000.times do |i|
        large_cache.put("key#{i}", "value#{i}")
      end

      # Measure access time
      start_time = Time.now
      1000.times do |i|
        large_cache.get("key#{i}")
      end
      duration = Time.now - start_time

      # Should be very fast (< 0.1 seconds for 1000 accesses)
      expect(duration).to be < 0.1
    end

    it 'provides O(1) put operation' do
      large_cache = LruCache.new(10_000)

      start_time = Time.now
      1000.times do |i|
        large_cache.put("key#{i}", "value#{i}")
      end
      duration = Time.now - start_time

      # Should be very fast (< 0.1 seconds for 1000 puts)
      expect(duration).to be < 0.1
    end

    it 'provides O(1) eviction' do
      cache = LruCache.new(1000)

      # Fill to capacity
      1000.times do |i|
        cache.put("key#{i}", "value#{i}")
      end

      # Measure eviction time (add 100 more items)
      start_time = Time.now
      100.times do |i|
        cache.put("newkey#{i}", "newvalue#{i}")
      end
      duration = Time.now - start_time

      # Eviction should be fast (< 0.01 seconds for 100 evictions)
      expect(duration).to be < 0.01
    end
  end

  describe 'Edge Cases' do
    it 'handles capacity of 1' do
      cache = LruCache.new(1)

      cache.put('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')

      cache.put('key2', 'value2')
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to eq('value2')
    end

    it 'handles nil values' do
      cache = LruCache.new(3)

      cache.put('key1', nil)
      expect(cache.key?('key1')).to be true
      expect(cache.get('key1')).to be_nil
    end

    it 'handles empty arrays as values' do
      cache = LruCache.new(3)

      cache.put('key1', [])
      expect(cache.get('key1')).to eq([])
    end

    it 'handles complex objects as values' do
      cache = LruCache.new(3)

      value = { a: 1, b: [2, 3], c: { d: 4 } }
      cache.put('key1', value)
      expect(cache.get('key1')).to eq(value)
    end
  end
end
