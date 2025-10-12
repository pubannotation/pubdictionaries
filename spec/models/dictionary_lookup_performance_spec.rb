# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dictionary, type: :model do
  describe '.find_labels_by_ids performance' do
    let(:user) { create(:user) }
    let!(:dict1) { create(:dictionary, user: user, name: 'dict1') }
    let!(:dict2) { create(:dictionary, user: user, name: 'dict2') }
    let!(:dict3) { create(:dictionary, user: user, name: 'dict3') }

    let!(:entries_dict1) do
      entries_data = Array.new(100) do |i|
        ["label_dict1_#{i}", "ID:#{i.to_s.rjust(6, '0')}", "label_dict1_#{i}", "label dict1 #{i}", 12, EntryMode::GRAY, false, dict1.id]
      end
      Entry.bulk_import(
        [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
        entries_data,
        validate: false
      )
      Entry.where(dictionary_id: dict1.id).to_a
    end

    let!(:entries_dict2) do
      entries_data = Array.new(100) do |i|
        ["label_dict2_#{i}", "ID:#{(i+100).to_s.rjust(6, '0')}", "label_dict2_#{i}", "label dict2 #{i}", 12, EntryMode::GRAY, false, dict2.id]
      end
      Entry.bulk_import(
        [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
        entries_data,
        validate: false
      )
      Entry.where(dictionary_id: dict2.id).to_a
    end

    let!(:entries_dict3) do
      entries_data = Array.new(100) do |i|
        ["label_dict3_#{i}", "ID:#{(i+200).to_s.rjust(6, '0')}", "label_dict3_#{i}", "label dict3 #{i}", 12, EntryMode::GRAY, false, dict3.id]
      end
      Entry.bulk_import(
        [:label, :identifier, :norm1, :norm2, :label_length, :mode, :dirty, :dictionary_id],
        entries_data,
        validate: false
      )
      Entry.where(dictionary_id: dict3.id).to_a
    end

    context 'with multiple dictionaries' do
      it 'uses minimal queries with eager loading (no N+1)' do
        # Get all identifiers from the 3 dictionaries (300 total)
        all_identifiers = (entries_dict1 + entries_dict2 + entries_dict3).map(&:identifier)
        dictionaries = [dict1, dict2, dict3]

        query_count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
        }

        result = nil
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          result = Dictionary.find_labels_by_ids(all_identifiers, dictionaries)
        end

        # Should be: 1 SELECT entries + 1 SELECT dictionaries + transaction overhead
        # Without the fix, this would be 301 queries (1 + 300 for each entry's dictionary)
        expect(query_count).to be <= 5, "Expected ≤5 queries but got #{query_count}"
      end

      it 'returns correct results' do
        all_identifiers = (entries_dict1 + entries_dict2 + entries_dict3).map(&:identifier)
        dictionaries = [dict1, dict2, dict3]

        result = Dictionary.find_labels_by_ids(all_identifiers, dictionaries)

        # Verify we got results for all identifiers
        expect(result.keys.size).to eq(300)

        # Verify structure
        first_entry = entries_dict1.first
        expect(result[first_entry.identifier]).to be_an(Array)
        expect(result[first_entry.identifier].first).to include(
          label: first_entry.label,
          dictionary: 'dict1'
        )
      end
    end

    context 'without specifying dictionaries' do
      it 'uses minimal queries for all entries' do
        # Get identifiers from all entries
        all_identifiers = Entry.pluck(:identifier)

        query_count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
        }

        result = nil
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          result = Dictionary.find_labels_by_ids(all_identifiers)
        end

        # Should be: 1 SELECT entries + 1 SELECT dictionaries
        expect(query_count).to be <= 5
      end
    end

    context 'performance benchmark' do
      it 'completes in reasonable time for 300 entries' do
        all_identifiers = (entries_dict1 + entries_dict2 + entries_dict3).map(&:identifier)
        dictionaries = [dict1, dict2, dict3]

        time = Benchmark.realtime do
          Dictionary.find_labels_by_ids(all_identifiers, dictionaries)
        end

        # Should complete in under 1 second
        # Without the fix, this would take 5+ seconds due to N+1 queries
        expect(time).to be < 1.0
      end
    end

    context 'with duplicate identifiers across dictionaries' do
      let!(:duplicate_entry) do
        # Create entry in dict2 with same identifier as one in dict1
        duplicate_id = entries_dict1.first.identifier
        Entry.create!(
          label: 'duplicate_label',
          identifier: duplicate_id,
          norm1: 'duplicate_label',
          norm2: 'duplicate_label',
          label_length: 15,
          mode: EntryMode::GRAY,
          dictionary: dict2
        )
      end

      it 'returns all entries for duplicate identifiers' do
        duplicate_id = entries_dict1.first.identifier
        dictionaries = [dict1, dict2]

        result = Dictionary.find_labels_by_ids([duplicate_id], dictionaries)

        # Should have 2 entries for the duplicate identifier
        expect(result[duplicate_id].size).to eq(2)
        expect(result[duplicate_id].map { |e| e[:dictionary] }).to contain_exactly('dict1', 'dict2')
      end
    end
  end

  describe '.find_dictionaries performance' do
    let(:user) { create(:user) }
    let!(:dict1) { create(:dictionary, user: user, name: 'test_dict_1') }
    let!(:dict2) { create(:dictionary, user: user, name: 'test_dict_2') }
    let!(:dict3) { create(:dictionary, user: user, name: 'test_dict_3') }
    let!(:dict4) { create(:dictionary, user: user, name: 'test_dict_4') }
    let!(:dict5) { create(:dictionary, user: user, name: 'test_dict_5') }

    context 'with multiple dictionary names' do
      it 'uses single query for multiple dictionaries' do
        names = ['test_dict_1', 'test_dict_2', 'test_dict_3', 'test_dict_4', 'test_dict_5']

        query_count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
        }

        result = nil
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          result = Dictionary.find_dictionaries(names)
        end

        # Should be exactly 1 query with WHERE IN clause
        # Without the fix, this would be 5 queries
        expect(query_count).to eq(1), "Expected 1 query but got #{query_count}"
      end

      it 'returns dictionaries in the requested order' do
        # Request in different order than creation
        names = ['test_dict_5', 'test_dict_1', 'test_dict_3']

        result = Dictionary.find_dictionaries(names)

        expect(result.map(&:name)).to eq(['test_dict_5', 'test_dict_1', 'test_dict_3'])
      end

      it 'returns correct dictionary objects' do
        names = ['test_dict_1', 'test_dict_2', 'test_dict_3']

        result = Dictionary.find_dictionaries(names)

        expect(result).to all(be_a(Dictionary))
        expect(result.size).to eq(3)
        expect(result[0].name).to eq('test_dict_1')
        expect(result[1].name).to eq('test_dict_2')
        expect(result[2].name).to eq('test_dict_3')
      end
    end

    context 'with unknown dictionary names' do
      it 'raises ArgumentError with all missing names' do
        names = ['test_dict_1', 'unknown_dict', 'test_dict_2', 'another_unknown']

        expect {
          Dictionary.find_dictionaries(names)
        }.to raise_error(ArgumentError, /unknown dictionary: unknown_dict, another_unknown/)
      end

      it 'raises ArgumentError for single missing dictionary' do
        names = ['test_dict_1', 'nonexistent']

        expect {
          Dictionary.find_dictionaries(names)
        }.to raise_error(ArgumentError, /unknown dictionary: nonexistent/)
      end
    end

    context 'with single dictionary' do
      it 'still uses single query (not N+1)' do
        names = ['test_dict_1']

        query_count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
        }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          Dictionary.find_dictionaries(names)
        end

        expect(query_count).to eq(1)
      end
    end

    context 'performance benchmark' do
      it 'completes in reasonable time for 10 dictionaries' do
        # Create 10 dictionaries
        dicts = Array.new(10) do |i|
          create(:dictionary, user: user, name: "perf_dict_#{i}")
        end
        names = dicts.map(&:name)

        time = Benchmark.realtime do
          Dictionary.find_dictionaries(names)
        end

        # Should complete in under 100ms
        # Without the fix with 10 dicts, this would take ~50ms (5ms per query)
        expect(time).to be < 0.1
      end
    end

    context 'with duplicate names' do
      it 'returns dictionary for each occurrence of name' do
        # Request same dictionary twice
        names = ['test_dict_1', 'test_dict_2', 'test_dict_1']

        result = Dictionary.find_dictionaries(names)

        expect(result.size).to eq(3)
        expect(result[0].name).to eq('test_dict_1')
        expect(result[1].name).to eq('test_dict_2')
        expect(result[2].name).to eq('test_dict_1')
        expect(result[0].id).to eq(result[2].id) # Same object
      end
    end
  end

  describe '.find_ids_by_labels with tag filtering' do
    let(:user) { create(:user) }
    let!(:dictionary) { create(:dictionary, user: user, name: 'tagged_dict', threshold: 1.0) }

    let!(:tag_chemistry) { create(:tag, dictionary: dictionary, value: 'chemistry') }
    let!(:tag_biology) { create(:tag, dictionary: dictionary, value: 'biology') }
    let!(:tag_medicine) { create(:tag, dictionary: dictionary, value: 'medicine') }

    # Entry with chemistry tag
    let!(:entry1) do
      entry = create(:entry,
        dictionary: dictionary,
        label: 'glucose',
        identifier: 'CHEBI:17234',
        norm1: 'glucose',
        norm2: 'glucose',
        mode: EntryMode::GRAY
      )
      create(:entry_tag, entry: entry, tag: tag_chemistry)
      entry
    end

    # Entry with biology tag
    let!(:entry2) do
      entry = create(:entry,
        dictionary: dictionary,
        label: 'protein',
        identifier: 'GO:0003674',
        norm1: 'protein',
        norm2: 'protein',
        mode: EntryMode::GRAY
      )
      create(:entry_tag, entry: entry, tag: tag_biology)
      entry
    end

    # Entry with both chemistry and biology tags
    let!(:entry3) do
      entry = create(:entry,
        dictionary: dictionary,
        label: 'enzyme',
        identifier: 'GO:0003824',
        norm1: 'enzyme',
        norm2: 'enzyme',
        mode: EntryMode::GRAY
      )
      create(:entry_tag, entry: entry, tag: tag_chemistry)
      create(:entry_tag, entry: entry, tag: tag_biology)
      entry
    end

    # Entry with all three tags
    let!(:entry4) do
      entry = create(:entry,
        dictionary: dictionary,
        label: 'insulin',
        identifier: 'CHEBI:145810',
        norm1: 'insulin',
        norm2: 'insulin',
        mode: EntryMode::GRAY
      )
      create(:entry_tag, entry: entry, tag: tag_chemistry)
      create(:entry_tag, entry: entry, tag: tag_biology)
      create(:entry_tag, entry: entry, tag: tag_medicine)
      entry
    end

    # Entry with no tags
    let!(:entry5) do
      create(:entry,
        dictionary: dictionary,
        label: 'water',
        identifier: 'CHEBI:15377',
        norm1: 'water',
        norm2: 'water',
        mode: EntryMode::GRAY
      )
    end

    context 'with single tag filter' do
      it 'returns only entries with specified tag' do
        result = Dictionary.find_ids_by_labels(
          ['glucose', 'protein', 'enzyme', 'insulin', 'water'],
          [dictionary],
          tags: ['chemistry'],
          verbose: true
        )

        # Should return: glucose (chemistry), enzyme (chemistry+biology), insulin (all 3)
        # Should NOT return: protein (biology only), water (no tags)
        expect(result['glucose'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:17234')
        expect(result['protein']).to be_empty
        expect(result['enzyme'].map { |e| e[:identifier] }).to contain_exactly('GO:0003824')
        expect(result['insulin'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:145810')
        expect(result['water']).to be_empty
      end

      it 'does not return duplicate entries (no duplicate rows from JOIN)' do
        # This tests the core fix: insulin has 3 tags, but should only appear once
        result = Dictionary.find_ids_by_labels(
          ['insulin'],
          [dictionary],
          tags: ['chemistry'],
          verbose: true
        )

        expect(result['insulin'].size).to eq(1)
        expect(result['insulin'].first[:identifier]).to eq('CHEBI:145810')
      end
    end

    context 'with multiple tag filters' do
      it 'returns only entries that have at least one of the specified tags' do
        result = Dictionary.find_ids_by_labels(
          ['glucose', 'protein', 'enzyme', 'insulin', 'water'],
          [dictionary],
          tags: ['chemistry', 'biology'],
          verbose: true
        )

        # All entries except water should match (water has no tags)
        expect(result['glucose'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:17234')
        expect(result['protein'].map { |e| e[:identifier] }).to contain_exactly('GO:0003674')
        expect(result['enzyme'].map { |e| e[:identifier] }).to contain_exactly('GO:0003824')
        expect(result['insulin'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:145810')
        expect(result['water']).to be_empty
      end

      it 'does not return duplicate entries when entry has multiple matching tags' do
        # enzyme has both chemistry and biology tags
        # insulin has all three tags (2 match)
        result = Dictionary.find_ids_by_labels(
          ['enzyme', 'insulin'],
          [dictionary],
          tags: ['chemistry', 'biology'],
          verbose: true
        )

        # Each should appear exactly once despite having multiple matching tags
        expect(result['enzyme'].size).to eq(1)
        expect(result['insulin'].size).to eq(1)
      end
    end

    context 'without tag filter' do
      it 'returns all matching entries regardless of tags' do
        result = Dictionary.find_ids_by_labels(
          ['glucose', 'protein', 'enzyme', 'insulin', 'water'],
          [dictionary],
          verbose: true
        )

        # All entries should match
        expect(result['glucose'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:17234')
        expect(result['protein'].map { |e| e[:identifier] }).to contain_exactly('GO:0003674')
        expect(result['enzyme'].map { |e| e[:identifier] }).to contain_exactly('GO:0003824')
        expect(result['insulin'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:145810')
        expect(result['water'].map { |e| e[:identifier] }).to contain_exactly('CHEBI:15377')
      end
    end

    context 'query count optimization' do
      it 'uses minimal queries when filtering by tags (no N+1)' do
        query_count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          query_count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql] =~ /^(BEGIN|COMMIT)/
        }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          Dictionary.find_ids_by_labels(
            ['glucose', 'protein', 'enzyme'],
            [dictionary],
            tags: ['chemistry', 'biology'],
            verbose: true
          )
        end

        # Should use minimal queries (not 1 query per entry per tag)
        # Expected: ~5-10 queries total for all 3 labels
        expect(query_count).to be <= 15, "Expected ≤15 queries but got #{query_count}"
      end

      it 'does not create duplicate database rows with tag filtering' do
        # This verifies the fix at the database level
        # Count actual SQL result rows vs Ruby result rows
        sql_row_count = 0
        ruby_result_count = 0

        # Hook into ActiveRecord to count SQL rows
        allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:exec_query) do |adapter, *args|
          result = adapter.send(:without_prepared_statement, *args) { adapter.send(:execute_and_clear, *args) }
          sql_row_count += result.count if args[0].to_s.include?('entries')
          result
        end

        result = Dictionary.find_ids_by_labels(
          ['insulin'],  # Has 3 tags
          [dictionary],
          tags: ['chemistry', 'biology'],
          verbose: true
        )

        ruby_result_count = result['insulin'].size

        # Ruby should see exactly 1 result (not duplicates)
        expect(ruby_result_count).to eq(1)
      end
    end

    context 'performance with many tags' do
      before do
        # Create 20 more entries, each with 5 tags
        20.times do |i|
          entry = create(:entry,
            dictionary: dictionary,
            label: "compound_#{i}",
            identifier: "COMPOUND:#{i.to_s.rjust(6, '0')}",
            norm1: "compound_#{i}",
            norm2: "compound #{i}",
            mode: EntryMode::GRAY
          )
          # Add chemistry and biology tags plus 3 random tags
          create(:entry_tag, entry: entry, tag: tag_chemistry)
          create(:entry_tag, entry: entry, tag: tag_biology)
          create(:entry_tag, entry: entry, tag: tag_medicine)
        end
      end

      it 'completes in reasonable time with tag filtering' do
        labels = (0...20).map { |i| "compound_#{i}" }

        time = Benchmark.realtime do
          Dictionary.find_ids_by_labels(
            labels,
            [dictionary],
            tags: ['chemistry', 'biology'],
            verbose: true
          )
        end

        # Should complete quickly despite many entries with many tags
        expect(time).to be < 1.0
      end

      it 'returns correct number of unique results' do
        labels = (0...20).map { |i| "compound_#{i}" }

        result = Dictionary.find_ids_by_labels(
          labels,
          [dictionary],
          tags: ['chemistry', 'biology'],
          verbose: true
        )

        # Each compound should appear exactly once
        labels.each do |label|
          expect(result[label].size).to eq(1), "#{label} should appear exactly once"
        end
      end
    end

    context 'with non-existent tags' do
      it 'returns empty results when filtering by non-existent tag' do
        result = Dictionary.find_ids_by_labels(
          ['glucose', 'protein'],
          [dictionary],
          tags: ['nonexistent_tag'],
          verbose: true
        )

        expect(result['glucose']).to be_empty
        expect(result['protein']).to be_empty
      end
    end
  end
end
