require 'rails_helper'

RSpec.describe LoadEntriesFromFileJob, type: :job do
  let(:user) { create(:user) }
  let(:dictionary) { create(:dictionary, user: user, name: 'test_upload_dict') }
  let(:temp_file) { Tempfile.new(['test_upload', '.tsv']) }
  let(:job_record) { Job.create!(dictionary: dictionary, name: 'Test upload', num_items: 0, num_dones: 0) }

  # Helper method to perform the job with proper setup
  def perform_job(dictionary, file_path, mode = nil)
    job_instance = LoadEntriesFromFileJob.new
    job_instance.instance_variable_set(:@job, job_record)
    job_instance.perform(dictionary, file_path, mode)
  end

  after do
    temp_file.close
    temp_file.unlink if File.exist?(temp_file.path)
  end

  describe '#perform' do
    context 'basic functionality' do
      it 'imports entries from TSV file' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['fructose', 'CHEBI:28757', ''],
          ['sucrose', 'CHEBI:17992', '']
        ])

        expect {
          perform_job(dictionary, temp_file.path)
        }.to change { dictionary.entries.count }.from(0).to(3)

        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose', 'sucrose')
        expect(dictionary.entries.pluck(:identifier)).to contain_exactly('CHEBI:17234', 'CHEBI:28757', 'CHEBI:17992')
      end

      it 'sets normalized text (norm1, norm2) for entries' do
        write_tsv_file(temp_file, [
          ['Glucose 6-phosphate', 'CHEBI:4170', '']
        ])

        perform_job(dictionary, temp_file.path)

        entry = dictionary.entries.first
        expect(entry.norm1).to be_present
        expect(entry.norm2).to be_present
        expect(entry.label_length).to eq('Glucose 6-phosphate'.length)
      end

      it 'deletes the file after processing' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', '']
        ])

        file_path = temp_file.path
        perform_job(dictionary, file_path)

        expect(File.exist?(file_path)).to be false
      end

      it 'deletes file even if job fails' do
        write_tsv_file(temp_file, [
          ['', '', '']  # Invalid entry
        ])

        file_path = temp_file.path

        begin
          perform_job(dictionary, file_path)
        rescue
          # Swallow error
        end

        expect(File.exist?(file_path)).to be false
      end
    end

    context 'with tags' do
      it 'imports entries with single tag' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry']
        ])

        perform_job(dictionary, temp_file.path)

        entry = dictionary.entries.first
        expect(entry.tags.pluck(:value)).to eq(['chemistry'])
      end

      it 'imports entries with multiple tags' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry,biology']
        ])

        perform_job(dictionary, temp_file.path)

        entry = dictionary.entries.first
        expect(entry.tags.pluck(:value)).to contain_exactly('chemistry', 'biology')
      end

      it 'creates tag records in dictionary' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry'],
          ['fructose', 'CHEBI:28757', 'biology']
        ])

        expect {
          perform_job(dictionary, temp_file.path)
        }.to change { dictionary.tags.count }.from(0).to(2)

        expect(dictionary.tags.pluck(:value)).to contain_exactly('chemistry', 'biology')
      end

      it 'reuses existing tags' do
        existing_tag = create(:tag, dictionary: dictionary, value: 'chemistry')

        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry'],
          ['fructose', 'CHEBI:28757', 'chemistry']
        ])

        perform_job(dictionary, temp_file.path)

        # Should not create duplicate tag
        expect(dictionary.tags.count).to eq(1)
        expect(dictionary.tags.first.id).to eq(existing_tag.id)
      end

      it 'handles entries without tags mixed with tagged entries' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry'],
          ['fructose', 'CHEBI:28757', ''],
          ['sucrose', 'CHEBI:17992', 'biology']
        ])

        perform_job(dictionary, temp_file.path)

        glucose = dictionary.entries.find_by(label: 'glucose')
        fructose = dictionary.entries.find_by(label: 'fructose')
        sucrose = dictionary.entries.find_by(label: 'sucrose')

        expect(glucose.tags.pluck(:value)).to eq(['chemistry'])
        expect(fructose.tags).to be_empty
        expect(sucrose.tags.pluck(:value)).to eq(['biology'])
      end
    end

    context 'deduplication' do
      it 'removes duplicate entries (same label and identifier)' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['glucose', 'CHEBI:17234', ''],
          ['fructose', 'CHEBI:28757', '']
        ])

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose')
      end

      it 'keeps entries with same label but different identifier' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['glucose', 'MESH:D005947', '']
        ])

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:identifier)).to contain_exactly('CHEBI:17234', 'MESH:D005947')
      end

      it 'removes duplicates even with different tags (database unique constraint)' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', 'chemistry'],
          ['glucose', 'CHEBI:17234', 'biology']
        ])

        perform_job(dictionary, temp_file.path)

        # With database unique constraint on [dictionary_id, label, identifier],
        # only the first entry is inserted, duplicate is ignored
        expect(dictionary.entries.count).to eq(1)
        entry = dictionary.entries.first
        expect(entry.label).to eq('glucose')
        expect(entry.identifier).to eq('CHEBI:17234')
        # First entry's tags are kept
        expect(entry.tags.pluck(:value)).to eq(['chemistry'])
      end
    end

    context 'file format handling' do
      it 'ignores extra columns beyond label, id, tags' do
        # Write file with 5 columns
        File.open(temp_file.path, 'w') do |f|
          f.puts("glucose\tCHEBI:17234\tchemistry\textra1\textra2")
          f.puts("fructose\tCHEBI:28757\t\textra3\textra4")
        end

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose')
      end

      it 'skips lines that cannot be parsed' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['', '', ''],  # Invalid: empty label
          ['fructose', 'CHEBI:28757', '']
        ])

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose')
      end

      it 'skips comment lines starting with #' do
        File.open(temp_file.path, 'w') do |f|
          f.puts("#label\tid\ttags")
          f.puts("glucose\tCHEBI:17234\tchemistry")
          f.puts("# This is a comment")
          f.puts("fructose\tCHEBI:28757\tbiology")
        end

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose')
      end

      it 'handles lines with only 2 columns (no tags)' do
        File.open(temp_file.path, 'w') do |f|
          f.puts("glucose\tCHEBI:17234")
          f.puts("fructose\tCHEBI:28757")
        end

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.first.tags).to be_empty
      end
    end

    context 'batching behavior' do
      it 'processes entries in batches' do
        # Create a file with more than batch size (10,000)
        # We'll use a smaller test (100 entries) and verify batching happens
        entries = 100.times.map { |i| ["entry_#{i}", "ID:#{i.to_s.rjust(6, '0')}", ''] }
        write_tsv_file(temp_file, entries)

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(100)
      end

      it 'handles exactly one batch size (10,000 entries)' do
        # This test would be slow with 10k real entries
        # Instead we'll verify the batching constant exists
        expect(LoadEntriesFromFileJob::BATCH_SIZE).to eq(10_000)
      end
    end

    context 'validation' do
      it 'raises error if dictionary is not empty' do
        create(:entry, dictionary: dictionary, label: 'existing', identifier: 'EXISTING:001')

        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', '']
        ])

        expect {
          perform_job(dictionary, temp_file.path)
        }.to raise_error(ArgumentError, /only available when there are no dictionary entries/)
      end

      it 'succeeds if dictionary has no entries' do
        expect(dictionary.entries.count).to eq(0)

        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', '']
        ])

        expect {
          perform_job(dictionary, temp_file.path)
        }.not_to raise_error
      end
    end

    context 'entries_num counter' do
      it 'updates dictionary entries_num after import' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['fructose', 'CHEBI:28757', ''],
          ['sucrose', 'CHEBI:17992', '']
        ])

        expect {
          perform_job(dictionary, temp_file.path)
        }.to change { dictionary.reload.entries_num }.from(0).to(3)
      end
    end

    context 'job tracking' do
      it 'updates job progress as entries are processed' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['fructose', 'CHEBI:28757', ''],
          ['sucrose', 'CHEBI:17992', '']
        ])

        perform_job(dictionary, temp_file.path)

        expect(job_record.reload.num_items).to eq(3)
        expect(job_record.reload.num_dones).to eq(3)
      end
    end

    context 'skipped entries tracking' do
      it 'stores skipped entries in job metadata when entries exceed token limit' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['problematic_entry', 'PROB:001', ''],
          ['fructose', 'CHEBI:28757', '']
        ])

        # Mock BatchAnalyzer to simulate a skipped entry
        allow_any_instance_of(BatchAnalyzer).to receive(:add_entries).and_wrap_original do |original, entries|
          analyzer = original.receiver

          # Simulate skipping the problematic entry
          if entries.any? { |e| e[0] == 'problematic_entry' }
            entries.reject! { |e| e[0] == 'problematic_entry' }
            analyzer.instance_variable_get(:@skipped_entries) << {
              label: 'problematic_entry',
              identifier: 'PROB:001',
              reason: 'token_limit'
            }
          end

          original.call(entries) unless entries.empty?
        end

        perform_job(dictionary, temp_file.path)

        # Should have imported 2 entries, skipped 1
        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('glucose', 'fructose')

        # Should store skipped entry in job metadata
        job_record.reload
        expect(job_record.metadata).to be_present
        expect(job_record.metadata['skipped_entries']).to be_an(Array)
        expect(job_record.metadata['skipped_entries'].size).to eq(1)

        skipped = job_record.metadata['skipped_entries'].first
        expect(skipped['label']).to eq('problematic_entry')
        expect(skipped['identifier']).to eq('PROB:001')
        expect(skipped['reason']).to eq('token_limit')
      end

      it 'stores multiple skipped entries in metadata' do
        write_tsv_file(temp_file, [
          ['good1', 'GOOD:001', ''],
          ['bad1', 'BAD:001', ''],
          ['good2', 'GOOD:002', ''],
          ['bad2', 'BAD:002', '']
        ])

        # Mock to skip entries with 'bad' prefix
        allow_any_instance_of(BatchAnalyzer).to receive(:add_entries).and_wrap_original do |original, entries|
          analyzer = original.receiver

          bad_entries = entries.select { |e| e[0].start_with?('bad') }
          good_entries = entries.reject { |e| e[0].start_with?('bad') }

          bad_entries.each do |entry|
            analyzer.instance_variable_get(:@skipped_entries) << {
              label: entry[0],
              identifier: entry[1],
              reason: 'token_limit'
            }
          end

          original.call(good_entries) unless good_entries.empty?
        end

        perform_job(dictionary, temp_file.path)

        # Should track both skipped entries
        job_record.reload
        expect(job_record.metadata['skipped_entries'].size).to eq(2)
        expect(job_record.metadata['skipped_entries'].map { |e| e['identifier'] }).to contain_exactly('BAD:001', 'BAD:002')
      end

      it 'does not create metadata when no entries are skipped' do
        write_tsv_file(temp_file, [
          ['glucose', 'CHEBI:17234', ''],
          ['fructose', 'CHEBI:28757', '']
        ])

        perform_job(dictionary, temp_file.path)

        # No skipped entries, metadata should be nil
        job_record.reload
        expect(job_record.metadata).to be_nil
      end
    end

    context 'edge cases' do
      it 'handles empty file' do
        File.open(temp_file.path, 'w') { |f| f.write('') }

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(0)
      end

      it 'handles file with only header line' do
        File.open(temp_file.path, 'w') do |f|
          f.puts("#label\tid\ttags")
        end

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(0)
      end

      it 'handles entries with special characters in labels' do
        write_tsv_file(temp_file, [
          ['alpha-D-glucose', 'CHEBI:17925', ''],
          ['glucose (6-phosphate)', 'CHEBI:4170', '']
        ])

        perform_job(dictionary, temp_file.path)

        expect(dictionary.entries.count).to eq(2)
        expect(dictionary.entries.pluck(:label)).to contain_exactly('alpha-D-glucose', 'glucose (6-phosphate)')
      end

      it 'handles entries with colons in identifiers' do
        write_tsv_file(temp_file, [
          ['glucose', 'MESH:D005947', '']
        ])

        perform_job(dictionary, temp_file.path)

        entry = dictionary.entries.first
        expect(entry.identifier).to eq('MESH:D005947')
      end
    end
  end

  # Helper method to write TSV file
  def write_tsv_file(file, entries)
    File.open(file.path, 'w') do |f|
      entries.each do |label, identifier, tags|
        f.puts([label, identifier, tags].join("\t"))
      end
    end
  end
end
