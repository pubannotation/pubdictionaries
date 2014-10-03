# encoding: utf-8
require 'spec_helper'

describe DictionariesController do
  describe 'id_mapping' do
    let(:dictionaries) { ['title_1', 'title_2']}
    let(:terms) { ['term_1', 'term_2']}
    let(:current_user) { FactoryGirl.create(:user) }
    before do
      controller.stub(:current_user).and_return(current_user)
    end

    context 'when Dictionary.find_showable_by_title blank' do
      let(:text_annotator) { double(:text_annotator) }
      before do
        Dictionary.stub(:find_showable_by_title).and_return(true)
        TextAnnotator.stub(:new).and_return(text_annotator)
        TextAnnotator.should_receive(:new).with(dictionaries[0], current_user)
        TextAnnotator.should_receive(:new).with(dictionaries[1], current_user)
        text_annotator.stub(:dictionary_exist?).and_return(true)
        text_annotator.stub(:terms_to_entrylists).and_return({'term' => [{dictionary_name: 'dictionary_name', uri: 'uri'}] })
        get :id_mapping, 'dictionaries' => dictionaries.to_json, 'terms' => terms.to_json, format: 'json'
      end

      it { expect(response.status).to eql(200) }
    end
  end
end
