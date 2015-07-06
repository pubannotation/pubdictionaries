# encoding: utf-8
require 'spec_helper'

describe ExpressionsUri do
  let(:expression) { FactoryGirl.create(:expression, words: 'words') }
  let(:uri) { FactoryGirl.create(:uri, resource: 'uri') }
  let(:dictionary) { FactoryGirl.create(:dictionary) }

  describe 'belongs_to' do
    let(:expressions_uri) { FactoryGirl.create(:expressions_uri, expression: expression, uri: uri, dictionary: dictionary) }

    describe 'belongs_to dictionary' do

      it 'is belongs_to dictionary' do
        expect( expressions_uri.dictionary ).to eql(dictionary)
      end
    end

    describe 'belongs_to expression' do
      it 'is belongs_to expression' do
        expect( expressions_uri.expression ).to eql(expression)
      end
    end

    describe 'belongs_to uri' do
      it 'is belongs_to uri' do
        expect( expressions_uri.uri ).to eql(uri)
      end
    end
  end

  describe 'validation' do
    context 'when same expression_id, uri_id and dictionary_id  present' do

      before do
        FactoryGirl.create(:expressions_uri, expression: expression, uri: uri, dictionary: dictionary)
      end

      it 'should be invalid' do
        expressions_uri = ExpressionsUri.new({expression_id: expression.id, uri_id: uri.id})
        expressions_uri.dictionary = dictionary                                      
        expect( expressions_uri.valid? ).to be_falsey
      end
    end
  end

  describe 'after_save' do
    let(:expression) { FactoryGirl.create(:expression)}
    let(:uri) { FactoryGirl.create(:uri)}
    let(:dictionary) { FactoryGirl.create(:dictionary)}
    let(:expressions_uri) { FactoryGirl.build(:expressions_uri, expression: expression, uri: uri, dictionary: dictionary) }

    it 'should call increment_dictionaries_count' do
      expect( expressions_uri ).to receive(:increment_dictionaries_count)
      expressions_uri.save
    end
  end

  describe 'after_destroy' do
    let(:expression) { FactoryGirl.create(:expression)}
    let(:uri) { FactoryGirl.create(:uri)}
    let(:dictionary) { FactoryGirl.create(:dictionary)}
    let(:expressions_uri) { FactoryGirl.create(:expressions_uri, expression: expression, uri: uri, dictionary: dictionary) }

    it 'should call decrement_dictionaries_count' do
      expect( expressions_uri ).to receive(:decrement_dictionaries_count)
      expressions_uri.destroy
    end
  end

  describe 'increment_dictionaries_count' do
    let(:expression) { FactoryGirl.create(:expression)}
    let(:uri) { FactoryGirl.create(:uri)}
    let(:dictionary) { FactoryGirl.create(:dictionary)}

    before do
      @expressions_uri = dictionary.expressions_uris.create(expression_id: expression.id, uri_id: uri.id)
      expression.reload
      uri.reload
    end

    it 'should increment expression.dictionaries_count' do
      expect{ 
        @expressions_uri.increment_dictionaries_count 
        expression.reload
      }.to change{ expression.dictionaries_count }.from(1).to(2)
    end

    it 'should increment uri.dictionaries_count' do
      expect{ 
        @expressions_uri.increment_dictionaries_count 
        uri.reload
      }.to change{ uri.dictionaries_count }.from(1).to(2)
    end
  end

  describe 'decrement_dictionaries_count' do
    let(:expression) { FactoryGirl.create(:expression)}
    let(:uri) { FactoryGirl.create(:uri)}
    let(:dictionary) { FactoryGirl.create(:dictionary)}

    before do
      @expressions_uri = dictionary.expressions_uris.create(expression_id: expression.id, uri_id: uri.id)
      expression.reload
      uri.reload
    end

    it 'should decrement expression.dictionaries_count' do
      expect{ 
        @expressions_uri.decrement_dictionaries_count 
        expression.reload
      }.to change{ expression.dictionaries_count }.from(1).to(0)
    end

    it 'should decrement uri.dictionaries_count' do
      expect{ 
        @expressions_uri.decrement_dictionaries_count 
        uri.reload
      }.to change{ uri.dictionaries_count }.from(1).to(0)
    end
  end
end
