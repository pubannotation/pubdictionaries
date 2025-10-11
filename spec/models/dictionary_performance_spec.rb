# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe Dictionary, type: :model do
  describe '#empty_entries performance' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user) }

    # Helper to count database queries
    def count_queries(&block)
      query_count = 0
      counter = lambda { |_name, _started, _finished, _unique_id, payload|
        query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      query_count
    end

    context 'with 1,000 entries' do
      before do
        # Create 1000 black entries
        entries_data = Array.new(1000) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::BLACK, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )
        dictionary.update_entries_num
      end

      it 'completes BLACK mode in under 5 seconds' do
        time = Benchmark.realtime { dictionary.empty_entries(EntryMode::BLACK) }
        expect(time).to be < 5.0
      end

      it 'uses minimal database queries for BLACK mode' do
        query_count = count_queries { dictionary.empty_entries(EntryMode::BLACK) }
        # Should be: 1 UPDATE + 1 COUNT + transaction overhead
        expect(query_count).to be <= 10
      end
    end

    context 'with 1,000 white entries' do
      before do
        entries_data = Array.new(1000) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::WHITE, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )
        dictionary.update_entries_num
      end

      it 'completes WHITE mode in under 5 seconds' do
        time = Benchmark.realtime { dictionary.empty_entries(EntryMode::WHITE) }
        expect(time).to be < 5.0
      end

      it 'uses minimal database queries for WHITE mode' do
        query_count = count_queries { dictionary.empty_entries(EntryMode::WHITE) }
        # Should be: 1 DELETE + 1 COUNT + transaction overhead
        expect(query_count).to be <= 10
      end
    end

    context 'with 1,000 gray entries' do
      before do
        entries_data = Array.new(1000) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::GRAY, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )
        dictionary.update_entries_num
      end

      it 'completes GRAY mode in under 5 seconds' do
        time = Benchmark.realtime { dictionary.empty_entries(EntryMode::GRAY) }
        expect(time).to be < 5.0
      end

      it 'uses minimal database queries for GRAY mode' do
        query_count = count_queries { dictionary.empty_entries(EntryMode::GRAY) }
        # Should be: 1 DELETE + 1 COUNT + transaction overhead
        expect(query_count).to be <= 10
      end
    end

    context 'with 1,000 auto_expanded entries' do
      before do
        entries_data = Array.new(1000) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::AUTO_EXPANDED, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )
        dictionary.update_entries_num
      end

      it 'completes AUTO_EXPANDED mode in under 5 seconds' do
        time = Benchmark.realtime { dictionary.empty_entries(EntryMode::AUTO_EXPANDED) }
        expect(time).to be < 5.0
      end

      it 'uses minimal database queries for AUTO_EXPANDED mode' do
        query_count = count_queries { dictionary.empty_entries(EntryMode::AUTO_EXPANDED) }
        # Should be: 1 DELETE + 1 COUNT + transaction overhead
        expect(query_count).to be <= 10
      end
    end

    context 'nil mode with 1,000 mixed entries' do
      before do
        # Create 250 entries of each type
        [EntryMode::GRAY, EntryMode::WHITE, EntryMode::BLACK, EntryMode::AUTO_EXPANDED].each do |mode|
          entries_data = Array.new(250) do |i|
            ["label_#{mode}_#{i}", "ID:#{mode}_#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, mode, false, dictionary.id]
          end
          Entry.bulk_import(
            [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
            entries_data,
            validate: false
          )
        end
        dictionary.update_entries_num
      end

      it 'completes nil mode in under 10 seconds' do
        time = Benchmark.realtime { dictionary.empty_entries(nil) }
        expect(time).to be < 10.0
      end

      it 'uses minimal database queries for nil mode' do
        query_count = count_queries { dictionary.empty_entries(nil) }
        # Should be: 1 DELETE entry_tags + 1 DELETE entries + 1 COUNT + transaction overhead
        expect(query_count).to be <= 10
      end
    end

    context 'memory usage for nil mode' do
      it 'does not load all entry IDs into memory' do
        # Create 10k entries
        entries_data = Array.new(10_000) do |i|
          ["label_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_#{i}", "label #{i}", 7, EntryMode::GRAY, false, dictionary.id]
        end
        Entry.bulk_import(
          [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
          entries_data,
          validate: false
        )

        # Verify it doesn't call pluck(:id) which loads into memory
        expect(dictionary.entries).not_to receive(:pluck)
        dictionary.empty_entries(nil)
      end
    end

    context 'query efficiency comparison' do
      it 'BLACK mode uses update_all instead of individual updates' do
        create_list(:entry, 100, :black, dictionary: dictionary)

        # Monitor for N+1 queries
        queries = []
        collector = lambda { |_name, _started, _finished, _unique_id, payload|
          queries << payload[:sql] if payload[:name] != 'SCHEMA'
        }

        ActiveSupport::Notifications.subscribed(collector, "sql.active_record") do
          dictionary.empty_entries(EntryMode::BLACK)
        end

        # Should NOT have 100 individual UPDATE queries
        update_queries = queries.select { |q| q =~ /UPDATE.*WHERE.*id = / }
        expect(update_queries.count).to eq(0), "Found individual UPDATE queries, should use bulk update_all"

        # Should have exactly ONE bulk UPDATE (matching entries table)
        bulk_updates = queries.select { |q| q =~ /UPDATE.*entries.*SET/ }
        expect(bulk_updates.count).to be >= 1, "Should have at least one bulk UPDATE query"
      end
    end
  end
end
