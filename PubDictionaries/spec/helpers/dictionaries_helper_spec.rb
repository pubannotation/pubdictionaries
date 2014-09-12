# encoding: utf-8
require 'spec_helper'

describe DictionariesHelper do
  describe 'dictionary_status' do
    before do
      @dictionary = double(:dictionary)
    end

    context 'when dictionary.unfinished? == true' do
      before do
        @dictionary.stub(:unfinished?).and_return(true)
      end

      it 'should return span with class unfinished_icon' do
        expect(helper.dictionary_status(@dictionary)).to match /unfinished_icon/
      end
    end

    context 'when dictionary.unfinished? == faj ' do
      before do
        @dictionary.stub(:unfinished?).and_return(false)
      end

      it 'should return span with class unfinished_icon' do
        expect(helper.dictionary_status(@dictionary)).to match /"finished_icon/
      end
    end
  end
end
