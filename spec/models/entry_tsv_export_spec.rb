require 'rails_helper'

RSpec.describe Entry, type: :model do
  describe '.as_tsv' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_dict') }

    context 'basic functionality' do
      it 'returns TSV string with header' do
        tsv = dictionary.entries.as_tsv
        expect(tsv).to be_a(String)
        expect(tsv).to start_with("#label\tid")
      end

      it 'returns header-only TSV when no entries exist' do
        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")
        expect(lines.length).to eq(1)
        expect(lines[0]).to eq("#label\tid")
      end

      it 'includes entry data in correct format' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines.length).to eq(2)
        expect(lines[0]).to eq("#label\tid")
        expect(lines[1]).to eq("glucose\tCHEBI:17234")
      end

      it 'handles multiple entries' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry, dictionary: dictionary, label: 'fructose', identifier: 'CHEBI:28757')
        create(:entry, dictionary: dictionary, label: 'sucrose', identifier: 'CHEBI:17992')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines.length).to eq(4)
        expect(tsv).to include('glucose')
        expect(tsv).to include('fructose')
        expect(tsv).to include('sucrose')
      end

      it 'uses tab as delimiter' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        # Header should have tab
        expect(lines[0]).to match(/\t/)
        # Data should have tab
        expect(lines[1]).to match(/\t/)
        # Should have exactly one tab per line
        expect(lines[1].count("\t")).to eq(1)
      end
    end

    context 'with tags' do
      let(:tag1) { create(:tag, dictionary: dictionary, value: 'chemistry') }
      let(:tag2) { create(:tag, dictionary: dictionary, value: 'biology') }

      it 'includes tags column header when entries have tags' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry_tag, entry: entry, tag: tag1)

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[0]).to eq("#label\tid\t#tags")
      end

      it 'includes single tag value' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry_tag, entry: entry, tag: tag1)

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose\tCHEBI:17234\tchemistry")
      end

      it 'includes multiple tags as comma-separated values' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry_tag, entry: entry, tag: tag1)
        create(:entry_tag, entry: entry, tag: tag2)

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[1]).to match(/glucose\tCHEBI:17234\t(chemistry,biology|biology,chemistry)/)
      end

      it 'handles entries without tags when other entries have tags' do
        entry_with_tags = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234')
        create(:entry_tag, entry: entry_with_tags, tag: tag1)

        entry_without_tags = create(:entry, dictionary: dictionary, label: 'fructose', identifier: 'CHEBI:28757')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[0]).to eq("#label\tid\t#tags")
        expect(lines.length).to eq(3)

        # One entry should have tags
        tagged_line = lines.find { |l| l.include?('glucose') }
        expect(tagged_line).to include('chemistry')

        # Other entry should not have tags (empty or no third column)
        untagged_line = lines.find { |l| l.include?('fructose') }
        expect(untagged_line).to match(/fructose\tCHEBI:28757(\t)?$/)
      end
    end

    context 'edge cases' do
      it 'handles labels with spaces' do
        create(:entry, dictionary: dictionary, label: 'glucose 6-phosphate', identifier: 'CHEBI:4170')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose 6-phosphate\tCHEBI:4170")
      end

      it 'handles labels with special characters' do
        create(:entry, dictionary: dictionary, label: 'alpha-D-glucose', identifier: 'CHEBI:17925')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[1]).to eq("alpha-D-glucose\tCHEBI:17925")
      end

      it 'handles labels with parentheses' do
        create(:entry, dictionary: dictionary, label: 'glucose (alpha-D)', identifier: 'CHEBI:17925')

        tsv = dictionary.entries.as_tsv

        expect(tsv).to include('glucose (alpha-D)')
      end

      it 'handles identifiers with colons' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'MESH:D005947')

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose\tMESH:D005947")
      end

      it 'handles identifiers with underscores' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'GO:0005996_test')

        tsv = dictionary.entries.as_tsv

        expect(tsv).to include('GO:0005996_test')
      end

      it 'handles long labels' do
        long_label = 'a' * 127  # Maximum allowed length
        create(:entry, dictionary: dictionary, label: long_label, identifier: 'TEST:001')

        tsv = dictionary.entries.as_tsv

        expect(tsv).to include(long_label)
      end

      it 'handles long identifiers' do
        long_id = 'PREFIX:' + 'X' * 240  # Near maximum
        create(:entry, dictionary: dictionary, label: 'test', identifier: long_id)

        tsv = dictionary.entries.as_tsv

        expect(tsv).to include(long_id)
      end
    end

    context 'with different entry modes' do
      it 'includes all entry modes (GRAY, WHITE, BLACK)' do
        create(:entry, dictionary: dictionary, label: 'gray_entry', identifier: 'TEST:001', mode: EntryMode::GRAY)
        create(:entry, dictionary: dictionary, label: 'white_entry', identifier: 'TEST:002', mode: EntryMode::WHITE)
        create(:entry, dictionary: dictionary, label: 'black_entry', identifier: 'TEST:003', mode: EntryMode::BLACK)

        tsv = dictionary.entries.as_tsv

        expect(tsv).to include('gray_entry')
        expect(tsv).to include('white_entry')
        expect(tsv).to include('black_entry')
      end

      it 'does not differentiate between modes in output' do
        create(:entry, dictionary: dictionary, label: 'entry1', identifier: 'TEST:001', mode: EntryMode::GRAY)
        create(:entry, dictionary: dictionary, label: 'entry2', identifier: 'TEST:002', mode: EntryMode::WHITE)

        tsv = dictionary.entries.as_tsv
        lines = tsv.split("\n")

        # Should have header + 2 data lines
        expect(lines.length).to eq(3)
        # Header should not have operator column
        expect(lines[0]).to eq("#label\tid")
      end
    end

    context 'when scoped to specific entries' do
      before do
        create(:entry, dictionary: dictionary, label: 'gray1', identifier: 'TEST:001', mode: EntryMode::GRAY)
        create(:entry, dictionary: dictionary, label: 'white1', identifier: 'TEST:002', mode: EntryMode::WHITE)
        create(:entry, dictionary: dictionary, label: 'black1', identifier: 'TEST:003', mode: EntryMode::BLACK)
      end

      it 'exports only scoped entries' do
        tsv = dictionary.entries.gray.as_tsv

        expect(tsv).to include('gray1')
        expect(tsv).not_to include('white1')
        expect(tsv).not_to include('black1')
      end

      it 'exports only WHITE entries' do
        tsv = dictionary.entries.white.as_tsv

        expect(tsv).not_to include('gray1')
        expect(tsv).to include('white1')
        expect(tsv).not_to include('black1')
      end

      it 'exports only active entries (GRAY + WHITE)' do
        tsv = dictionary.entries.active.as_tsv

        expect(tsv).to include('gray1')
        expect(tsv).to include('white1')
        expect(tsv).not_to include('black1')
      end
    end
  end

  describe '.as_tsv_v' do
    let(:user) { create(:user) }
    let(:dictionary) { create(:dictionary, user: user, name: 'test_dict') }

    context 'basic functionality' do
      it 'returns TSV string with operator column' do
        tsv = dictionary.entries.as_tsv_v
        expect(tsv).to be_a(String)
        expect(tsv).to start_with("#label\tid\toperator")
      end

      it 'returns header-only TSV when no entries exist' do
        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")
        expect(lines.length).to eq(1)
        expect(lines[0]).to eq("#label\tid\toperator")
      end

      it 'includes operator for WHITE entries' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::WHITE)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose\tCHEBI:17234\t+")
      end

      it 'includes operator for BLACK entries' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::BLACK)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose\tCHEBI:17234\t-")
      end

      it 'does not include operator for GRAY entries' do
        create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::GRAY)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        # Operator should be empty/nil for GRAY
        expect(lines[1]).to match(/glucose\tCHEBI:17234\t$/)
      end

      it 'handles mixed entry modes' do
        create(:entry, dictionary: dictionary, label: 'white_entry', identifier: 'TEST:001', mode: EntryMode::WHITE)
        create(:entry, dictionary: dictionary, label: 'black_entry', identifier: 'TEST:002', mode: EntryMode::BLACK)
        create(:entry, dictionary: dictionary, label: 'gray_entry', identifier: 'TEST:003', mode: EntryMode::GRAY)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines.length).to eq(4)

        white_line = lines.find { |l| l.include?('white_entry') }
        expect(white_line).to end_with("\t+")

        black_line = lines.find { |l| l.include?('black_entry') }
        expect(black_line).to end_with("\t-")
      end
    end

    context 'with tags' do
      let(:tag1) { create(:tag, dictionary: dictionary, value: 'chemistry') }

      it 'includes tags column when entries have tags' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::WHITE)
        create(:entry_tag, entry: entry, tag: tag1)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[0]).to eq("#label\tid\t#tags\toperator")
      end

      it 'includes tags and operator together' do
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::WHITE)
        create(:entry_tag, entry: entry, tag: tag1)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[1]).to eq("glucose\tCHEBI:17234\tchemistry\t+")
      end

      it 'includes multiple tags with operator' do
        tag2 = create(:tag, dictionary: dictionary, value: 'biology')
        entry = create(:entry, dictionary: dictionary, label: 'glucose', identifier: 'CHEBI:17234', mode: EntryMode::BLACK)
        create(:entry_tag, entry: entry, tag: tag1)
        create(:entry_tag, entry: entry, tag: tag2)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[1]).to match(/glucose\tCHEBI:17234\t(chemistry,biology|biology,chemistry)\t-/)
      end
    end

    context 'edge cases' do
      it 'handles labels with special characters and operator' do
        create(:entry, dictionary: dictionary, label: 'alpha-D-glucose', identifier: 'CHEBI:17925', mode: EntryMode::WHITE)

        tsv = dictionary.entries.as_tsv_v
        lines = tsv.split("\n")

        expect(lines[1]).to eq("alpha-D-glucose\tCHEBI:17925\t+")
      end
    end
  end
end
