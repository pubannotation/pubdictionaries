require 'rails_helper'
require 'zip'

RSpec.describe Dictionary, type: :model do
  describe '#create_downloadable!' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_export_dict') }

    after do
      # Clean up created files
      if File.exist?(dictionary.downloadable_zip_path)
        File.delete(dictionary.downloadable_zip_path)
      end
    end

    context 'basic functionality' do
      it 'creates a ZIP file' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        expect(File.exist?(dictionary.downloadable_zip_path)).to be true
        expect(File.size(dictionary.downloadable_zip_path)).to be > 0
      end

      it 'creates the downloadables directory if it does not exist' do
        # Remove directory if it exists
        FileUtils.rm_rf(Dictionary::DOWNLOADABLES_DIR)

        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        dictionary.create_downloadable!

        expect(Dir.exist?(Dictionary::DOWNLOADABLES_DIR)).to be true
      end

      it 'creates a valid ZIP file that can be opened' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        expect {
          Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
            # Should not raise error
          end
        }.not_to raise_error
      end

      it 'includes a CSV file with dictionary name' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          entry_names = zip_file.entries.map(&:name)
          expect(entry_names).to include("#{dictionary.name}.csv")
        end
      end

      it 'overwrites existing ZIP file' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        # Create first version
        dictionary.create_downloadable!
        first_mtime = File.mtime(dictionary.downloadable_zip_path)

        # Wait a moment to ensure different timestamp
        sleep 0.1

        # Add another entry
        create(:entry, dictionary: dictionary, label: 'fructose', identifier: 'CHEBI:28757')

        # Create second version
        dictionary.create_downloadable!
        second_mtime = File.mtime(dictionary.downloadable_zip_path)

        expect(second_mtime).to be > first_mtime
      end
    end

    context 'ZIP file contents' do
      it 'contains TSV data with correct header' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          expect(lines[0]).to eq("#label\tid")
          expect(lines[1]).to eq("glucose\tCHEBI:17234")
        end
      end

      it 'contains all entries' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry, dictionary: dictionary, label: 'fructose', identifier: 'CHEBI:28757')
        create(:entry, dictionary: dictionary, label: 'sucrose', identifier: 'CHEBI:17992')

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          expect(content).to include('glucose')
          expect(content).to include('fructose')
          expect(content).to include('sucrose')

          lines = content.split("\n")
          expect(lines.length).to eq(4)  # header + 3 entries
        end
      end

      it 'contains entries with tags' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        tag = create(:tag, dictionary: dictionary, value: 'chemistry')
        create(:entry_tag, entry: entry, tag: tag)

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          expect(lines[0]).to eq("#label\tid\t#tags")
          expect(lines[1]).to eq("glucose\tCHEBI:17234\tchemistry")
        end
      end

      it 'handles empty dictionary' do
        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          expect(lines.length).to eq(1)  # Only header
          expect(lines[0]).to eq("#label\tid")
        end
      end

      it 'exports correct TSV format (tab-separated)' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          # Each line should have exactly one tab
          expect(lines[1].count("\t")).to eq(1)
        end
      end
    end

    context 'with large number of entries' do
      it 'handles 100 entries efficiently' do
        100.times do |i|
          create(:entry,
            dictionary: dictionary,
            label: "entry_#{i}",
            identifier: "TEST:#{i.to_s.rjust(6, '0')}"
          )
        end

        time = Benchmark.realtime do
          dictionary.create_downloadable!
        end

        # Should complete in reasonable time
        expect(time).to be < 5.0

        # Verify file was created and contains all entries
        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          expect(lines.length).to eq(101)  # header + 100 entries
        end
      end

      it 'handles entries with tags efficiently' do
        50.times do |i|
          entry = create(:entry,
            dictionary: dictionary,
            label: "entry_#{i}",
            identifier: "TEST:#{i.to_s.rjust(6, '0')}"
          )
          tag = create(:tag, dictionary: dictionary, value: "tag_#{i}")
          create(:entry_tag, entry: entry, tag: tag)
        end

        time = Benchmark.realtime do
          dictionary.create_downloadable!
        end

        expect(time).to be < 5.0

        # Verify tags are included
        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          lines = content.split("\n")
          expect(lines[0]).to eq("#label\tid\t#tags")
          expect(lines.length).to eq(51)  # header + 50 entries
        end
      end
    end

    context 'with different entry modes' do
      it 'includes all entry modes in export' do
        create(:entry, dictionary: dictionary, label: 'gray_entry', identifier: 'TEST:001', mode: EntryMode::GRAY)
        create(:entry, dictionary: dictionary, label: 'white_entry', identifier: 'TEST:002', mode: EntryMode::WHITE)
        create(:entry, dictionary: dictionary, label: 'black_entry', identifier: 'TEST:003', mode: EntryMode::BLACK)

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          content = csv_entry.get_input_stream.read

          expect(content).to include('gray_entry')
          expect(content).to include('white_entry')
          expect(content).to include('black_entry')
        end
      end
    end

    context 'error handling' do
      it 'raises error if downloadables directory cannot be created' do
        # Make DOWNLOADABLES_DIR point to an unwritable location
        stub_const('Dictionary::DOWNLOADABLES_DIR', '/root/unwritable/')

        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        expect {
          dictionary.create_downloadable!
        }.to raise_error(Errno::EACCES)
      end
    end

    context 'file path and naming' do
      it 'uses correct file path' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        expected_path = File.join(Dictionary::DOWNLOADABLES_DIR, "#{dictionary.filename}.zip")
        expect(dictionary.downloadable_zip_path).to eq(expected_path)
        expect(File.exist?(expected_path)).to be true
      end

      it 'uses dictionary filename for ZIP file' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        expect(File.basename(dictionary.downloadable_zip_path, '.zip')).to eq(dictionary.filename)
      end

      it 'uses dictionary name for CSV file inside ZIP' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        dictionary.create_downloadable!

        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          entry_names = zip_file.entries.map(&:name)
          expect(entry_names).to include("#{dictionary.name}.csv")
        end
      end
    end

    context 'ZIP compression' do
      it 'produces smaller file than uncompressed TSV' do
        # Create many entries to test compression
        50.times do |i|
          create(:entry,
            dictionary: dictionary,
            label: "test_entry_with_long_label_#{i}",
            identifier: "TEST:#{i.to_s.rjust(6, '0')}"
          )
        end

        dictionary.create_downloadable!

        # Get uncompressed size
        uncompressed_size = 0
        Zip::File.open(dictionary.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{dictionary.name}.csv")
          uncompressed_size = csv_entry.size
        end

        compressed_size = File.size(dictionary.downloadable_zip_path)

        # Compressed should be smaller than uncompressed
        expect(compressed_size).to be < uncompressed_size
      end
    end

    context 'with special characters in dictionary name' do
      let(:special_dict) { create(:dictionary, user: user, name: 'test_dict_2024') }

      after do
        if File.exist?(special_dict.downloadable_zip_path)
          File.delete(special_dict.downloadable_zip_path)
        end
      end

      it 'handles dictionary name with underscores and numbers' do
        create(:entry, dictionary: special_dict, label: 'glucose', identifier: 'CHEBI:17234')

        special_dict.create_downloadable!

        expect(File.exist?(special_dict.downloadable_zip_path)).to be true

        Zip::File.open(special_dict.downloadable_zip_path) do |zip_file|
          csv_entry = zip_file.find_entry("#{special_dict.name}.csv")
          expect(csv_entry).not_to be_nil
        end
      end
    end
  end

  describe '#downloadable_zip_path' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_dict') }

    it 'returns path in DOWNLOADABLES_DIR' do
      path = dictionary.downloadable_zip_path
      expect(path).to start_with(Dictionary::DOWNLOADABLES_DIR)
    end

    it 'returns path with .zip extension' do
      path = dictionary.downloadable_zip_path
      expect(path).to end_with('.zip')
    end

    it 'uses dictionary filename' do
      path = dictionary.downloadable_zip_path
      expect(path).to include(dictionary.filename)
    end

    it 'caches the path' do
      path1 = dictionary.downloadable_zip_path
      path2 = dictionary.downloadable_zip_path
      expect(path1.object_id).to eq(path2.object_id)
    end
  end
end
