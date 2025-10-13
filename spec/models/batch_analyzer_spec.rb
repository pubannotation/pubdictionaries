require 'rails_helper'

RSpec.describe BatchAnalyzer do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_dict') }
  let(:analyzer) { BatchAnalyzer.new(dictionary) }

  after do
    analyzer.shutdown
  end

  describe '#add_entries' do
    context 'with normal entries (no token limit errors)' do
      it 'processes entries successfully' do
        entries = [
          ['glucose', 'CHEBI:17234', []],
          ['fructose', 'CHEBI:28757', []],
          ['sucrose', 'CHEBI:17992', []]
        ]

        expect {
          analyzer.add_entries(entries)
        }.to change { dictionary.entries.count }.from(0).to(3)

        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose', 'sucrose')
      end

      it 'sets norm1 and norm2 for entries' do
        entries = [['Glucose 6-phosphate', 'CHEBI:4170', []]]

        analyzer.add_entries(entries)

        entry = dictionary.entries.first
        expect(entry.norm1).to be_present
        expect(entry.norm2).to be_present
        expect(entry.label).to eq('Glucose 6-phosphate')
      end
    end

    context 'when Elasticsearch token limit is exceeded' do
      it 'uses binary search to find and skip problematic entry' do
        # Create a mix of normal and problematic entries
        normal_entries = [
          ['glucose', 'CHEBI:17234', []],
          ['fructose', 'CHEBI:28757', []],
          ['sucrose', 'CHEBI:17992', []],
          ['lactose', 'CHEBI:17716', []]
        ]

        # Mock normalize to fail when batch contains 'fructose'
        allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
          if labels.include?('fructose')
            # Simulate Elasticsearch token limit error
            raise '{"error":{"type":"illegal_state_exception","reason":"The number of tokens produced by calling _analyze has exceeded the allowed maximum of [10000]."},"status":500}'
          else
            # Call original for non-problematic batches
            original.call(labels, *normalizers)
          end
        end

        # Should process 3 entries (skipping 'fructose')
        expect {
          analyzer.add_entries(normal_entries)
        }.to change { dictionary.entries.count }.by(3)

        # 'fructose' should be skipped
        expect(dictionary.entries.pluck(:label)).not_to include('fructose')
        expect(dictionary.entries.pluck(:label)).to include('glucose', 'sucrose', 'lactose')

        # Should track the skipped entry
        expect(analyzer.skipped_entries.size).to eq(1)
        expect(analyzer.skipped_entries.first[:label]).to eq('fructose')
        expect(analyzer.skipped_entries.first[:identifier]).to eq('CHEBI:28757')
      end

      it 'handles multiple problematic entries in batch' do
        entries = [
          ['good1', 'ID:001', []],
          ['bad1', 'ID:002', []],
          ['good2', 'ID:003', []],
          ['bad2', 'ID:004', []],
          ['good3', 'ID:005', []]
        ]

        # Mock normalize to fail on any batch with 'bad1' or 'bad2'
        allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
          problematic = ['bad1', 'bad2']
          has_problematic = (labels & problematic).any?

          if has_problematic
            raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count exceeded"}}'
          else
            original.call(labels, *normalizers)
          end
        end

        # Should process only the 3 good entries
        expect {
          analyzer.add_entries(entries)
        }.to change { dictionary.entries.count }.by(3)

        expect(dictionary.entries.pluck(:identifier)).to contain_exactly('ID:001', 'ID:003', 'ID:005')

        # Should track both skipped entries
        expect(analyzer.skipped_entries.size).to eq(2)
        expect(analyzer.skipped_entries.map { |e| e[:identifier] }).to contain_exactly('ID:002', 'ID:004')
      end
    end

    context 'binary search behavior' do
      it 'logs when batch fails and binary search starts' do
        entries = [
          ['entry1', 'ID:001', []],
          ['problematic', 'ID:002', []]
        ]

        allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
          if labels.include?('problematic')
            raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
          else
            original.call(labels, *normalizers)
          end
        end

        expect(Rails.logger).to receive(:warn).with(/Batch of 2 entries failed token limit/)
        expect(Rails.logger).to receive(:warn).with(/Skipped entry.*problematic.*ID:002/)

        analyzer.add_entries(entries)
      end

      it 'processes large batches efficiently' do
        # Create 100 entries with one problematic in the middle
        entries = 100.times.map do |i|
          label = i == 50 ? 'problematic_entry' : "entry_#{i}"
          [label, "ID:#{i.to_s.rjust(3, '0')}", []]
        end

        allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
          if labels.include?('problematic_entry')
            raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
          else
            original.call(labels, *normalizers)
          end
        end

        # Should process 99 good entries
        expect {
          analyzer.add_entries(entries)
        }.to change { dictionary.entries.count }.by(99)

        # Verify problematic entry was skipped
        expect(dictionary.entries.where(label: 'problematic_entry')).to be_empty
      end
    end

    context 'error handling for non-token-limit errors' do
      it 're-raises non-token-limit Elasticsearch errors' do
        entries = [['glucose', 'CHEBI:17234', []]]

        # Simulate different kind of error
        allow(analyzer).to receive(:normalize).and_raise(
          '{"error":{"type":"index_not_found_exception","reason":"no such index"}}'
        )

        expect {
          analyzer.add_entries(entries)
        }.to raise_error(/index_not_found_exception/)
      end

      it 're-raises database errors' do
        entries = [['glucose', 'CHEBI:17234', []]]

        allow(dictionary).to receive(:add_entries).and_raise(
          ActiveRecord::RecordInvalid.new
        )

        expect {
          analyzer.add_entries(entries)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '#add_entries_with_binary_search' do
    it 'returns immediately for empty entries array' do
      expect(analyzer.send(:add_entries_with_binary_search, [])).to be_nil
    end

    it 'logs and skips single problematic entry' do
      entries = [['problematic', 'ID:BAD', []]]

      allow(analyzer).to receive(:normalize).and_raise(
        '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
      )

      expect(Rails.logger).to receive(:warn).with(/Skipped entry.*problematic.*ID:BAD/)

      analyzer.send(:add_entries_with_binary_search, entries)

      expect(dictionary.entries).to be_empty
    end

    it 'splits batch and processes recursively' do
      entries = [
        ['good1', 'ID:001', []],
        ['good2', 'ID:002', []],
        ['bad', 'ID:003', []],
        ['good3', 'ID:004', []]
      ]

      call_count = 0
      allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
        call_count += 1

        if labels.include?('bad')
          raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
        else
          original.call(labels, *normalizers)
        end
      end

      analyzer.send(:add_entries_with_binary_search, entries)

      # Should have split and processed good entries
      expect(dictionary.entries.count).to eq(3)
      expect(dictionary.entries.pluck(:identifier)).to contain_exactly('ID:001', 'ID:002', 'ID:004')

      # Binary search should make fewer calls than sequential (4 entries, ~3-5 calls vs 4)
      expect(call_count).to be <= 6
    end

    it 'logs depth during recursive splitting' do
      entries = [
        ['a', 'ID:1', []],
        ['b', 'ID:2', []],
        ['c', 'ID:3', []],
        ['d', 'ID:4', []]
      ]

      allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
        if labels.include?('c')
          raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
        else
          original.call(labels, *normalizers)
        end
      end

      # Allow other debug calls (like SQL logs) but ensure our splitting message appears at least once
      allow(Rails.logger).to receive(:debug).and_call_original
      expect(Rails.logger).to receive(:debug).with(/Splitting batch.*depth/).at_least(:once).and_call_original

      analyzer.send(:add_entries_with_binary_search, entries)
    end
  end

  describe 'performance characteristics' do
    it 'handles batch of 1000 entries with one problematic entry efficiently' do
      entries = 1000.times.map do |i|
        label = i == 500 ? 'problematic' : "entry_#{i}"
        [label, "ID:#{i.to_s.rjust(4, '0')}", []]
      end

      normalize_call_count = 0
      allow(analyzer).to receive(:normalize).and_wrap_original do |original, labels, *normalizers|
        normalize_call_count += 1

        if labels.include?('problematic')
          raise '{"error":{"type":"illegal_state_exception","reason":"max_token_count"}}'
        else
          original.call(labels, *normalizers)
        end
      end

      analyzer.add_entries(entries)

      # Binary search should make ~log2(1000) ≈ 10 additional calls
      # Much better than 1000 sequential calls
      expect(normalize_call_count).to be <= 20
      expect(dictionary.entries.count).to eq(999)
    end
  end
end
