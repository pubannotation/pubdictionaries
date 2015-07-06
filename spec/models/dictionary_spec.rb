# encoding: utf-8
require 'spec_helper'

describe Dictionary do
  describe 'cleanup' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:dictionary_1) { FactoryGirl.create(:dictionary) }
    let(:expression_1) { FactoryGirl.create(:expression) }
    let(:uri_1) { FactoryGirl.create(:uri) }

    before do
      FactoryGirl.create(:expressions_uri, dictionary: dictionary_1, expression: expression_1, uri: uri_1)
      FactoryGirl.create(:expressions_uri, dictionary: dictionary, expression: expression_1, uri: uri_1)
      5.times do
        expression = FactoryGirl.create(:expression)
        uri = FactoryGirl.create(:uri)
        FactoryGirl.create(:expressions_uri, dictionary: dictionary, expression: expression, uri: uri)
      end
      expression_1.reload
      uri_1.reload
    end

    it 'should delete expressions where dictionaries_count == 1' do
      expect{ dictionary.cleanup }.to change{ Expression.count }.from(6).to(1)
    end

    it 'should decrement expression.dictionaries_count where dictionaries_count > 1' do
      expect{ 
        dictionary.cleanup
        expression_1.reload
      }.to change{ expression_1.dictionaries_count }.from(2).to(1)
    end

    it 'should delete uris where dictionaries_count == 1' do
      expect{ dictionary.cleanup }.to change{ Uri.count }.from(6).to(1)
    end

    it 'should decrement uri.dictionaries_count where dictionaries_count > 1' do
      expect{ 
        dictionary.cleanup
        uri_1.reload
      }.to change{ uri_1.dictionaries_count }.from(2).to(1)
    end

    it 'should delete uris where dictionaries_count == 1' do
      expect{ dictionary.cleanup }.to change{ ExpressionsUri.count }.from(7).to(1)
    end
  end

  describe 'import_expressions_from_file' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:separator) { ',' }
    let(:file) { 'file' }

    context 'when import_expressions return false' do
      before do
        allow( dictionary ).to receive(:import_expressions).and_return(false)
      end

      it { expect( dictionary.import_expressions_from_file(nil, nil) ).to be_falsey }

      it 'should call cleanup' do
        expect( dictionary ).to receive(:cleanup)
        dictionary.import_expressions_from_file(file, separator)
      end
    end

    context 'when import_expressions return true' do
      before do
        allow( dictionary ).to receive(:import_expressions).and_return(true)
        allow( File ).to receive(:delete).and_return(nil)
      end

      it 'should call import_expressions with file and separator' do
        expect( dictionary ).to receive(:import_expressions).with(file, separator)
        dictionary.import_expressions_from_file(file, separator)
      end

      it 'should call File.delete' do
        expect( File ).to receive(:delete).with(file)
        dictionary.import_expressions_from_file(file, separator)
      end

      it 'should change created_by_delayed_job to true' do
        expect{ 
          dictionary.import_expressions_from_file(file, separator) 
          dictionary.reload
        }.to change{ dictionary.created_by_delayed_job }.from(false).to(true)
      end

      it 'should call elasticsearch indexing by delayed_job' do
        expect( Delayed::Job ).to receive(:enqueue).at_least(:twice)
        dictionary.import_expressions_from_file(file, separator)
      end

      it 'should call save dictionary' do
        expect( dictionary ).to receive(:save)
        dictionary.import_expressions_from_file(file, separator)
      end
    end
  end

  describe 'import_expressions' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:opened_file) { double(:file) }
    let(:sep) { ',' }

    before do
      allow(File).to receive(:open).and_return(opened_file)
      allow(opened_file).to receive(:close).and_return(nil)
      allow( dictionary ).to receive(:read_expressions).and_return([])
    end

    context 'when file is nil' do
      it 'should add error_messages' do
        dictionary.import_expressions(nil, '')
        expect( dictionary.error_messages ).to include('File stream is nil')
      end

      it 'should return false' do
        expect( dictionary.import_expressions(nil, '') ).to be_falsey
      end
    end

    context 'when file present' do
      let(:file) { 'file.csv' }

      it 'should open file' do
        expect( File ).to receive(:open).with(file, textmode: true)
        dictionary.import_expressions(file, sep)
      end

      it 'should call reaad_expressions' do
        expect( dictionary ).to receive(:read_expressions).with(opened_file, sep, 0)
        dictionary.import_expressions(file, sep)
      end

      it 'should close file' do
        expect( opened_file ).to receive(:close)
        dictionary.import_expressions(file, sep)
      end
    end
  end

  describe 'read_expressions' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:fp) { File.open("#{Rails.root}/spec/files/dictionary.csv") }
    let(:sep) { ',' }
    
    before do
      allow( dictionary ).to receive(:parse_raw_expression) do |line, sep|
        line.split(sep)
      end
      allow( dictionary ).to receive(:save_expressions_uris) do |words, uri|
        [words, uri]
      end
    end

    it 'should call is_proper_raw_expression?' do
      expect( dictionary ).to receive(:is_proper_raw_expression?).at_least(:once)
      dictionary.read_expressions(fp, sep, 0)
    end

    it 'should call parse_raw_expression' do
      expect( dictionary ).to receive(:parse_raw_expression).at_least(:once)
      dictionary.read_expressions(fp, sep, 0)
    end

    it 'should call save_expressions_uris' do
      expect( dictionary ).to receive(:save_expressions_uris).at_least(:once).with('word_1', 'http://uri/1')
      expect( dictionary ).to receive(:save_expressions_uris).at_least(:once).with('word_2', 'http://uri/2')
      expect( dictionary ).to receive(:save_expressions_uris).at_least(:once).with('word_3', 'http://uri/3')
      dictionary.read_expressions(fp, sep, 0)
    end

    it 'should return expressions generated by save_expressions_uris' do
      expect( dictionary.read_expressions(fp, sep, 0) ).to eql([ ['word_1', 'http://uri/1'], ['word_2', 'http://uri/2'], ['word_3', 'http://uri/3'] ])
    end
  end

  describe 'is_proper_raw_expression?' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }

    context 'when line is blank' do
      it { expect( dictionary.is_proper_raw_expression?('', nil, nil) ).to be_falsey }
    end

    context 'wehn line items < 2' do
      it { expect( dictionary.is_proper_raw_expression?('item', ',', 0) ).to be_falsey }
    end

    context 'wehn item length > 255' do
      it '' do
        dictionary.is_proper_raw_expression?("#{ '0123456789' * 30 },222", ',', 0)
        expect( dictionary.error_messages ).to include('longer than 255')
      end

      it { expect( dictionary.is_proper_raw_expression?("#{ '0123456789' * 30 },222", ',', 0) ).to be_falsey }
    end

    context 'when line is proper' do
      it { expect( dictionary.is_proper_raw_expression?('word,uri', ',', 0) ).to be_truthy }
    end
  end

  describe 'parse_raw_expression' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:sep) { ',' }
    let(:line_1) { "word" }
    let(:line_2) { "uri" }
    let(:line) { "#{ line_1 }#{ sep }#{ line_2 }" }

    context 'when line consists 2 items' do
      it { expect( dictionary.parse_raw_expression(line, sep) ).to match_array([line_1, line_2]) }
    end

    context 'when line consists larger than 2 items' do
      it { expect( dictionary.parse_raw_expression("#{ line },third", sep) ).to match_array([line_1, line_2]) }
    end
  end

  describe 'save_expression_uris' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:words) { 'words' }
    let(:uri) { 'uri' }
    let(:expressions_uris) { double(:expressions_uris) }

    describe 'expression' do
      context 'when save expression is blank' do
        it 'should create new expression' do
          expect{ dictionary.save_expressions_uris(words, uri) }.to change{ Expression.count }.from(0).to(1)
        end
      end

      context 'when save expression is present' do
        before do
          FactoryGirl.create(:expression, words: words)
        end

        it 'should not create new expression' do
          expect{ dictionary.save_expressions_uris(words, uri) }.not_to change{ Expression.count }
        end
      end
    end

    describe 'uri' do
      context 'when save uri is blank' do
        it 'should create new uri' do
          expect{ dictionary.save_expressions_uris(words, uri) }.to change{ Uri.count }.from(0).to(1)
        end
      end

      context 'when save uri is present' do
        before do
          FactoryGirl.create(:uri, resource: uri)
        end

        it 'should not create new uri' do
          expect{ dictionary.save_expressions_uris(words, uri) }.not_to change{ Uri.count }
        end
      end
    end

    describe 'expressions_uris' do
      context 'when same expression uri and dictionary_id is blank' do
        it 'should create new expressions_uris' do
          expect{ dictionary.save_expressions_uris(words, uri) }.to change{ ExpressionsUri.count }.from(0).to(1)
        end
      end

      context 'when same expression uri and dictionary_id is present' do
        let(:same_expression) { FactoryGirl.create(:expression, words: words) }
        let(:same_uri) { FactoryGirl.create(:uri, resource: uri) }

        before do
          FactoryGirl.create(:expressions_uri, expression: same_expression, uri: same_uri, dictionary: dictionary)
        end

        it 'should be invalid' do
          expressions_uri = dictionary.expressions_uris.build(expression_id: same_expression.id, uri_id: same_uri.id)
          expect( expressions_uri.valid? ).to be_falsey
        end

        it 'should not create new expressions_uris' do
          expect{ dictionary.save_expressions_uris(words, uri) }.not_to change{ ExpressionsUri.count }
        end
      end
    end
  end

  describe 'import_entries' do
    before do
      @dictionary = FactoryGirl.create(:dictionary, created_by_delayed_job: false) 
    end

    context 'when file is nil' do
      it 'should return false' do
        expect(@dictionary.send(:import_entries, nil, 'sep')).to be_falsey
      end

      it 'should add dictionary.error_messages' do
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
