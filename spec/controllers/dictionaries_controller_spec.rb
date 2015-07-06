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

  describe 'edit' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:current_user) { FactoryGirl.create(:user) }

    before do
      controller.stub(:current_user).and_return(current_user)
      controller.class.skip_before_filter :authenticate_user!
      allow( Dictionary ).to receive(:find_showable_by_title).and_return(dictionary)
    end

    it 'should call find_showable_by_title with dictionary.title and current_user' do
      expect( Dictionary ).to receive(:find_showable_by_title).with(dictionary.title, current_user)
      get :edit, id: dictionary.title
    end
  end

  describe 'update' do
    let(:dictionary) { FactoryGirl.create(:dictionary) }
    let(:current_user) { FactoryGirl.create(:user) }
    let(:dictionary_param){ { 'title' => dictionary.title, 'file' => ''} }

    before do
      controller.stub(:current_user).and_return(current_user)
      controller.class.skip_before_filter :authenticate_user!
      allow( Dictionary ).to receive(:find_showable_by_title).and_return(dictionary)
      allow( Dictionary ).to receive(:cleanup).and_return(nil)
      allow( controller ).to receive(:run_create_as_a_delayed_job).and_return(nil)
    end

    it 'should call find_showable_by_title with dictionary.title and current_user' do
      expect( Dictionary ).to receive(:find_showable_by_title).with(dictionary.title, current_user)
      get :update, id: dictionary.title, dictionary: dictionary_param
    end

    it 'should update dictionary' do
      expect( dictionary ).to receive(:update_attributes).with(dictionary_param)
      get :update, id: dictionary.title, dictionary: dictionary_param
    end

    it 'should redirect_to dictionaries_path' do
      get :update, id: dictionary.title, dictionary: dictionary_param
      expect( response ).to redirect_to(dictionaries_path(dictionary_type: 'my_dic'))
    end

    context 'when file present' do
      let(:dictionary_param){ { title: dictionary.title, file: 'file/path'} }

      it 'should set notice' do
        get :update, id: dictionary.title, dictionary: dictionary_param
        expect( flash[:notice] ).to be_present
      end

      it 'should cleanup dictionary' do
        expect( dictionary ).to receive(:cleanup)
        get :update, id: dictionary.title, dictionary: dictionary_param
      end

      it 'should import expressions' do
        expect( controller ).to receive(:run_create_as_a_delayed_job)
        get :update, id: dictionary.title, dictionary: dictionary_param
      end

      it 'should import expressions' do
        expect( controller ).to receive(:run_create_as_a_delayed_job)
        get :update, id: dictionary.title, dictionary: dictionary_param
      end
    end

    context 'when file blank' do
      let(:dictionary_param){ { title: dictionary.title, file: ''} }

      it 'should not set notice' do
        get :update, id: dictionary.title, dictionary: dictionary_param
        expect( flash[:notice] ).to be_blank
      end

      it 'should not cleanup dictionary' do
        expect( dictionary ).not_to receive(:cleanup)
        get :update, id: dictionary.title, dictionary: dictionary_param
      end

      it 'should not import expressions' do
        expect( controller ).not_to receive(:run_create_as_a_delayed_job)
        get :update, id: dictionary.title, dictionary: dictionary_param
      end
    end
  end
end
