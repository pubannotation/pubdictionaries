# encoding: utf-8
require 'spec_helper'

describe Dictionary do
  describe 'import_entries' do
    before do
      @dictionary = FactoryGirl.create(:dictionary, created_by_delayed_job: false) 
    end

    context 'when file is nil' do
      it 'should return false' do
        expect(@dictionary.send(:import_entries, nil, 'sep')).to be_falsey
      end

      it 'shoud add dictionary.error_messages' do
        expect{@dictionary.send(:import_entries, nil, 'sep')}.to change{@dictionary.error_messages}
      end
    end

    context 'when file is present' do
      before do
        @file = "entry_name,id,label"
        File.stub(:open).and_return(@file)
        @file.stub(:close).and_return(nil)
        @read_entries = Entry.new(view_title: 'vt', search_title: 'st', uri: 'http', label: 'label')
      end

      context 'when read_entries return values' do
        before do
          @dictionary.stub(:read_entries).and_return([@read_entries], [])
          @dictionary.entries.should_receive(:import).with([@read_entries])
          @result = @dictionary.send(:import_entries, @file, 'sep')
        end

        it 'should return true' do
          expect(@result).to be_truthy
        end
      end

      context 'when read_entries is blank' do
        before do
          @dictionary.stub(:read_entries).and_return([])
          @result = @dictionary.send(:import_entries, @file, 'sep')
          @dictionary.entries.should_not_receive(:import)
        end

        it 'should return true' do
          expect(@result).to be_truthy
        end
      end
    end
  end

  describe 'read_entries' do
    before do
      @dictionary = FactoryGirl.create(:dictionary) 
      @fp = File.open("#{Rails.root}/spec/files/entries.txt")
      @dictionary.stub(:is_proper_raw_entry?).and_return(true)
      @dictionary.stub(:parse_raw_entry_from).and_return(nil)
    end

    context 'when is_proper_raw_entry? == true' do
      before do
        @dictionary.stub(:assemble_entry_from).and_return('entry')
        @result = @dictionary.send(:read_entries, @fp, ',', 1000, 0)
      end

      it 'should return entries parse_raw_entry_from, and assemble_entry_from' do
        expect(@result).to eql ['entry', 'entry']
      end
    end
  end

  describe 'is_proper_raw_entry?' do
    before do
      @dictionary = FactoryGirl.create(:dictionary) 
    end

    context 'when line is blank' do
      it 'should return false' do
        expect(@dictionary.send(:is_proper_raw_entry?, '', ',', nil)).to be_falsey
      end
    end 

    context 'when line is present' do
      context 'when item.length <= 255' do
        context 'when items.size == 3' do
          before do
            @line = '1,2,3'
            @result = @dictionary.send(:is_proper_raw_entry?, @line, ',', nil)
          end
        
          it 'should return true' do
            expect(@result).to be_truthy
          end
        end

        context 'when items.size < 2' do
          before do
            @line = '1'
            @result = @dictionary.send(:is_proper_raw_entry?, @line, ',', nil)
          end
        
          it 'should return error_messages about items.size' do
            expect(@dictionary.error_messages).to include('less than')
          end
        
          it 'should return false' do
            expect(@result).to be_falsey
          end
        end

        context 'when items.size > 3' do
          before do
            @line = '1,2,3,4'
            @result = @dictionary.send(:is_proper_raw_entry?, @line, ',', nil)
          end
        
          it 'should return error_messages about items.size' do
            expect(@dictionary.error_messages).to include('less than')
          end
        
          it 'should return false' do
            expect(@result).to be_falsey
          end
        end
      end

      context 'when item.length > 255' do
        context 'when items.size == 3' do
          before do
            @line = '123' * 100
            @result = @dictionary.send(:is_proper_raw_entry?, @line, ',', nil)
          end
        
          it 'should return error_messages about item.length' do
            expect(@dictionary.error_messages).to include('longer than')
          end
        
          it 'should return false' do
            expect(@result).to be_falsey
          end
        end
      end
    end
  end

  describe 'parse_raw_entry_from' do
    before do
      @dictionary = FactoryGirl.create(:dictionary, created_by_delayed_job: false) 
      @item_0 = 'item0'
      @item_1 = 'item1'
      @item_2 = 'item2'
    end

    context 'when items.size == 2' do
      before do
        @line = "#{@item_0},#{@item_1}"
      end

      it 'should rturn items and blank string' do
        expect(@dictionary.send(:parse_raw_entry_from, @line, ',')).to eql([@item_0, @item_1, ""])
      end
    end

    context 'when items.size != 2' do
      before do
        @line = "#{@item_0},#{@item_1},#{@item_2}"
      end

      it 'should rturn items' do
        expect(@dictionary.send(:parse_raw_entry_from, @line, ',')).to eql([@item_0, @item_1, @item_2])
      end
    end
  end

  describe 'assemble_entry_from' do
    before do
      @dictionary = FactoryGirl.create(:dictionary, created_by_delayed_job: false) 
      @title = 'title'
      @uri = 'uri'
      @label = 'label'
      @normalize_str = 'normarlize'
      @dictionary.stub(:normalize_str).and_return(@normalize_str)
      @result = @dictionary.send(:assemble_entry_from, @title, @uri, @label)
    end

    it 'should set dictionary.id as dictionary_id' do
      expect(@result.dictionary_id).to eql(@dictionary.id)
    end

    it 'should set title as view_title' do
      expect(@result.view_title).to eql(@title)
    end

    it 'should set normalize_str as search_title' do
      expect(@result.search_title).to eql(@normalize_str)
    end

    it 'should set uri as uri' do
      expect(@result.uri).to eql(@uri)
    end

    it 'should set uri as uri' do
      expect(@result.label).to eql(@label)
    end
  end

  describe 'create_ssdb' do
    before do
      @dictionary = FactoryGirl.create(:dictionary) 
      FactoryGirl.create(:entry, dictionary_id: @dictionary.id)
      @dictionary.reload
    end

    context 'db.insert successfully' do
      before do
        db = double(:db)
        Simstring::Writer.stub(:new).and_return(db)
        db.stub(:insert).and_return(nil)
        db.stub(:close).and_return(nil)
      end

      it 'should return true' do
        expect(@dictionary.send(:create_ssdb)).to be_truthy
      end
    end

    context 'db.insert unsuccessfully' do
      before do
        Simstring::Writer.stub(:new).and_raise('Error')
      end

      it 'should return false' do
        expect(@dictionary.send(:create_ssdb)).to be_falsey
      end
    end
  end

  describe 'import_entries_and_create_simstring_db' do
    before do
      @dictionary = FactoryGirl.create(:dictionary, created_by_delayed_job: false) 
      Entry.stub(:delete_all).and_return(nil)
      @dictionary.stub(:delete_ssdb).and_return(nil)
      File.stub(:delete).and_return(nil)
    end

    describe 'import_entries' do
      before do
        @dictionary.stub(:create_ssdb).and_return(true)
      end

      context 'when import_entries == true' do
        before do
          @dictionary.stub(:import_entries).and_return(true)
          Entry.should_not_receive(:delete_all)
          File.should_receive(:delete)
          @dictionary.should_receive(:save)
        end

        it 'should update dictionary.created_by_delayed_job to true' do
          expect{@dictionary.import_entries_and_create_simstring_db('', ',')}.to change{@dictionary.created_by_delayed_job}.from(false).to(true)
        end
      end

      context 'when import_entries == false' do
        before do
          @dictionary.stub(:import_entries).and_return(false)
          Entry.should_receive(:delete_all).with(["dictionary_id = ?", @dictionary.id])
          File.should_not_receive(:delete)
          @dictionary.should_not_receive(:save)
        end

        it 'shoud return false' do
          expect(@dictionary.import_entries_and_create_simstring_db('', ',')).to be_falsey
        end

        it 'should not update dictionary.created_by_delayed_job to true' do
          expect{@dictionary.import_entries_and_create_simstring_db('', ',')}.not_to change{@dictionary.created_by_delayed_job}.from(false)
        end
      end
    end

    describe 'create_ssdb' do
      before do
        @dictionary.stub(:import_entries).and_return(true)
      end

      context 'when create_ssdb == true' do
        before do
          @dictionary.stub(:create_ssdb).and_return(true)
          Entry.should_not_receive(:delete_all)
          @dictionary.should_receive(:save)
        end

        it 'should update dictionary.created_by_delayed_job to true' do
          expect{@dictionary.import_entries_and_create_simstring_db('', ',')}.to change{@dictionary.created_by_delayed_job}.from(false).to(true)
        end
      end

      context 'when crete_ssdb == false' do
        before do
          @dictionary.stub(:create_ssdb).and_return(false)
          File.should_not_receive(:delete)
          @dictionary.should_not_receive(:save)
          @dictionary.import_entries_and_create_simstring_db('', ',')
        end

        it 'should not update dictionary.created_by_delayed_job to true' do
          expect{@dictionary.import_entries_and_create_simstring_db('', ',')}.not_to change{@dictionary.created_by_delayed_job}.from(false)
        end
      end
    end
  end
end
