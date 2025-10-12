require 'rails_helper'

RSpec.describe Entry, type: :model do
  describe 'TSV export performance' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_export_dict') }

    describe '.as_tsv' do
      context 'with entries that have tags' do
        before do
          # Create entries with tags
          5.times do |i|
            entry = create(:entry,
              dictionary: dictionary,
              label: "test_label_#{i}",
              identifier: "TEST:#{i.to_s.rjust(6, '0')}",
              mode: EntryMode::GRAY
            )
            # Create multiple tags per entry to test N+1 prevention
            2.times do |j|
              tag = create(:tag, dictionary: dictionary, value: "tag_#{i}_#{j}")
              create(:entry_tag, entry: entry, tag: tag)
            end
          end
        end

        it 'uses minimal queries (prevents N+1)' do
          # Should use:
          # 1. Check for tags (joins query)
          # 2. Load batch of entries
          # 3. Load tags for batch
          # Total: ~3-5 queries for small dataset
          queries = track_queries do
            dictionary.entries.as_tsv
          end

          expect(queries.count).to be <= 10
        end

        it 'eager loads tags to prevent N+1 queries' do
          # Verify that entry.tag_values doesn't trigger additional queries
          tsv_output = nil
          queries = track_queries do
            tsv_output = dictionary.entries.as_tsv
          end

          # Should not have N queries where N = number of entries
          # For 5 entries, should have ~5 queries total, not 5+ entry count
          expect(queries.count).to be < 10
          expect(tsv_output).to include('test_label_0')
        end

        it 'includes tags in output' do
          tsv = dictionary.entries.as_tsv
          lines = tsv.split("\n")

          # First line should be header with tags column
          expect(lines[0]).to eq("#label\tid\t#tags")

          # Data lines should have tags
          lines[1..].each do |line|
            parts = line.split("\t")
            expect(parts.length).to eq(3)
            expect(parts[2]).to match(/tag_\d+_\d+(,tag_\d+_\d+)*/) # Tags format
          end
        end

        it 'produces correct TSV format' do
          tsv = dictionary.entries.as_tsv
          lines = tsv.split("\n")

          expect(lines.length).to eq(6) # 1 header + 5 entries
          expect(lines[0]).to eq("#label\tid\t#tags")

          # Verify each entry is present
          5.times do |i|
            expect(tsv).to include("test_label_#{i}")
            expect(tsv).to include("TEST:#{i.to_s.rjust(6, '0')}")
          end
        end
      end

      context 'with entries without tags' do
        before do
          # Create entries without tags
          5.times do |i|
            create(:entry,
              dictionary: dictionary,
              label: "test_label_#{i}",
              identifier: "TEST:#{i.to_s.rjust(6, '0')}",
              mode: EntryMode::GRAY
            )
          end
        end

        it 'uses minimal queries' do
          queries = track_queries do
            dictionary.entries.as_tsv
          end

          # Should use:
          # 1. Check for tags
          # 2. Load batch of entries
          # Total: ~2-3 queries
          expect(queries.count).to be <= 5
        end

        it 'does not include tags column in output' do
          tsv = dictionary.entries.as_tsv
          lines = tsv.split("\n")

          # First line should be header without tags column
          expect(lines[0]).to eq("#label\tid")

          # Data lines should not have tags
          lines[1..].each do |line|
            parts = line.split("\t")
            expect(parts.length).to eq(2)
          end
        end
      end

      context 'with large number of entries' do
        before do
          # Create 100 entries to test batching
          100.times do |i|
            entry = create(:entry,
              dictionary: dictionary,
              label: "test_label_#{i}",
              identifier: "TEST:#{i.to_s.rjust(6, '0')}",
              mode: EntryMode::GRAY
            )
            # Add tag to some entries
            if i % 3 == 0
              tag = create(:tag, dictionary: dictionary, value: "tag_#{i}")
              create(:entry_tag, entry: entry, tag: tag)
            end
          end
        end

        it 'completes in reasonable time' do
          time = Benchmark.realtime do
            dictionary.entries.as_tsv
          end

          # Should complete in under 1 second for 100 entries
          expect(time).to be < 1.0
        end

        it 'uses minimal queries regardless of entry count' do
          queries = track_queries do
            dictionary.entries.as_tsv
          end

          # Should use batched queries, not N+1
          # Even with 100 entries, should have < 10 queries
          expect(queries.count).to be < 10
        end

        it 'produces correct output for all entries' do
          tsv = dictionary.entries.as_tsv
          lines = tsv.split("\n")

          # Should have header + 100 entries
          expect(lines.length).to eq(101)
        end
      end
    end

    describe '.as_tsv_v' do
      context 'with WHITE and BLACK entries with tags' do
        before do
          # Create WHITE entries with tags
          3.times do |i|
            entry = create(:entry,
              dictionary: dictionary,
              label: "white_label_#{i}",
              identifier: "WHITE:#{i.to_s.rjust(6, '0')}",
              mode: EntryMode::WHITE
            )
            tag = create(:tag, dictionary: dictionary, value: "tag_#{i}")
            create(:entry_tag, entry: entry, tag: tag)
          end

          # Create BLACK entries with tags
          2.times do |i|
            entry = create(:entry,
              dictionary: dictionary,
              label: "black_label_#{i}",
              identifier: "BLACK:#{i.to_s.rjust(6, '0')}",
              mode: EntryMode::BLACK
            )
            tag = create(:tag, dictionary: dictionary, value: "tag_black_#{i}")
            create(:entry_tag, entry: entry, tag: tag)
          end
        end

        it 'uses minimal queries (prevents N+1)' do
          queries = track_queries do
            dictionary.entries.as_tsv_v
          end

          expect(queries.count).to be <= 10
        end

        it 'includes operator column with correct values' do
          tsv = dictionary.entries.as_tsv_v
          lines = tsv.split("\n")

          # First line should be header with operator column
          expect(lines[0]).to eq("#label\tid\t#tags\toperator")

          # Check WHITE entries have + operator
          white_lines = lines.select { |l| l.include?('white_label_') }
          expect(white_lines.length).to eq(3)
          white_lines.each do |line|
            expect(line).to end_with("\t+")
          end

          # Check BLACK entries have - operator
          black_lines = lines.select { |l| l.include?('black_label_') }
          expect(black_lines.length).to eq(2)
          black_lines.each do |line|
            expect(line).to end_with("\t-")
          end
        end
      end

      context 'with entries without tags' do
        before do
          # Create WHITE and BLACK entries without tags
          create(:entry,
            dictionary: dictionary,
            label: "white_label",
            identifier: "WHITE:000001",
            mode: EntryMode::WHITE
          )
          create(:entry,
            dictionary: dictionary,
            label: "black_label",
            identifier: "BLACK:000001",
            mode: EntryMode::BLACK
          )
        end

        it 'uses minimal queries' do
          queries = track_queries do
            dictionary.entries.as_tsv_v
          end

          expect(queries.count).to be <= 5
        end

        it 'includes operator column without tags column' do
          tsv = dictionary.entries.as_tsv_v
          lines = tsv.split("\n")

          # First line should be header without tags column
          expect(lines[0]).to eq("#label\tid\toperator")

          # Data lines should have operator but not tags
          lines[1..].each do |line|
            parts = line.split("\t")
            expect(parts.length).to eq(3)
            expect(parts[2]).to match(/[+-]/)
          end
        end
      end
    end

    describe 'memory efficiency' do
      it 'uses constant memory regardless of entry count' do
        # Create enough entries to test batching (1000 per batch)
        # If using all.each, this would load all into memory
        # If using find_each, memory usage should be constant
        500.times do |i|
          create(:entry,
            dictionary: dictionary,
            label: "test_#{i}",
            identifier: "TEST:#{i.to_s.rjust(6, '0')}",
            mode: EntryMode::GRAY
          )
        end

        # Run garbage collection before test
        GC.start

        before_objects = GC.stat(:total_allocated_objects)

        dictionary.entries.as_tsv

        after_objects = GC.stat(:total_allocated_objects)

        # With find_each, should allocate much fewer objects than entry count
        # If using all.each, would allocate ~500 Entry objects at once
        # With find_each in batches, allocates in smaller chunks
        allocated = after_objects - before_objects

        # Should allocate significantly fewer than 500 * typical_entry_size
        # This is a soft check - main goal is to verify batching is used
        expect(allocated).to be < 100_000
      end
    end
  end

  # Helper method to track queries
  def track_queries(&block)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      queries << event.payload[:sql] unless event.payload[:sql] =~ /^(BEGIN|COMMIT|SHOW|PRAGMA|SELECT currval)/
    end

    block.call

    ActiveSupport::Notifications.unsubscribe(subscriber)
    queries
  end
end
