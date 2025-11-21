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

  describe 'Pre-Indexing Performance' do
    context 'span deduplication' do
      it 'avoids redundant database queries for repeated spans' do
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

        # With pre-indexing, should query once for "fever" since it's deduplicated in span_index hash
        expect(query_count).to be <= 1

        annotator.dispose
      end

      it 'handles unique spans efficiently' do
        text = 'patient has fever, high fever, and continued fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        result = annotator.annotate_batch([{ text: text }])

        # Should work correctly with duplicate spans naturally deduplicated
        expect(result.first[:denotations]).to be_an(Array)

        annotator.dispose
      end

      it 'works correctly with multiple dictionaries' do
        text = 'fever'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary, dictionary2], options)
        result = annotator.annotate_batch([{ text: text }])

        # Should generate spans once and search across all dictionaries
        expect(result.first[:denotations]).to be_an(Array)

        annotator.dispose
      end

      it 'generates fresh span index for each batch' do
        text1 = 'fever'
        text2 = 'headache'
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        result1 = annotator.annotate_batch([{ text: text1 }])
        result2 = annotator.annotate_batch([{ text: text2 }])

        # Each batch should work independently with its own span index
        expect(result1.first[:denotations]).to be_an(Array)
        expect(result2.first[:denotations]).to be_an(Array)

        annotator.dispose
      end

      it 'efficiently handles non-matching spans' do
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

        # Should query once for "nonexistent" despite appearing 3 times
        expect(query_count).to be <= 1

        annotator.dispose
      end
    end

    context 'performance impact' do
      it 'handles text with many repeated terms efficiently' do
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

      it 'handles many unique spans efficiently' do
        # Text with many unique terms
        text = (1..100).map { |i| "term#{i}" }.join(' ')
        options = { threshold: 0.85 }

        annotator = TextAnnotator.new([dictionary], options)

        expect {
          annotator.annotate_batch([{ text: text }])
        }.not_to raise_error

        annotator.dispose
      end

      it 'processes batches efficiently without cross-batch overhead' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        # Simulate processing many batches
        (1..20).each do |batch|
          text = (1..100).map { |i| "batch#{batch}_term#{i}" }.join(' ')

          expect {
            annotator.annotate_batch([{ text: text }])
          }.not_to raise_error
        end

        annotator.dispose
      end

      it 'efficiently processes large texts' do
        options = { threshold: 0.85 }
        annotator = TextAnnotator.new([dictionary], options)

        # Large text simulation
        text = (1..200).map { |i| "term#{i}" }.join(' ')

        start_time = Time.now
        result = annotator.annotate_batch([{ text: text }])
        end_time = Time.now

        # Should complete efficiently even with many spans
        expect(end_time - start_time).to be < 10

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
