# encoding: utf-8
require 'spec_helper'

describe TextAnnotator do
  let(:current_user) { FactoryGirl.create(:user) }
  describe '#initialize' do
    let(:ssr) { 'ssr' }
    let(:query_builder) { 'query_builder' }
    let(:pproc) { 'pproc' }
    before {
      QUERY_BUILDER.stub(:new).and_return(query_builder)
      POST_PROCESSOR.stub(:new).and_return(pproc)
      SIMSTRING_RETRIEVER.stub(:new).and_return(ssr)
    }

    describe '@ssr' do
      context 'when dictionary_exist? == true' do
        before do
          POSTGRESQL_RETRIEVER.stub_chain(:new, :dictionary_exist?).and_return(true)
        end
        let(:dictionary) { FactoryGirl.create(:dictionary, title: 'Search') }
        let(:text_annotator) { TextAnnotator.new(dictionary.title, current_user) }

        it { expect(text_annotator.instance_variable_get(:@ssr)).to eql(ssr) }
      end

      context 'when dictionary_exist? == false' do
        before do
          POSTGRESQL_RETRIEVER.stub_chain(:new, :dictionary_exist?).and_return(false)
        end
        let(:text_annotator) { TextAnnotator.new('title', current_user) }

        it { expect(text_annotator.instance_variable_get(:@ssr)).to be_nil }
      end
    end

    describe 'another instance variables' do
      let(:text_annotator) { TextAnnotator.new('title', current_user) }

      it { expect(text_annotator.instance_variable_get(:@qbuilder)).to eql(query_builder) }
      it { expect(text_annotator.instance_variable_get(:@pproc)).to eql(pproc) }
    end
  end

  describe '.ids_to_labels' do
    let(:labels) { [{label: 'label_1'}, {label: 'label_2'}] }
    let(:text_annotator) { TextAnnotator.new('title', current_user) }
    let(:ids) { ['id1', 'id2'] }
    let(:pgr) { double(:pgr) }
    before { 
      text_annotator.instance_variable_set(:@pgr, pgr)
      pgr.stub(:get_entries_from_db).and_return(labels) 
      TextAnnotator.stub(:initialize).and_return(nil)
    }

    it { 
      pgr.should_receive(:get_entries_from_db).with(ids[0], :uri)
      pgr.should_receive(:get_entries_from_db).with(ids[1], :uri)
      text_annotator.ids_to_labels(ids, nil)
    }

    it { expect(text_annotator.ids_to_labels(ids, nil)).to eql({ids[0] => [labels[0][:label], labels[1][:label]], ids[1] => [labels[0][:label], labels[1][:label]]}) }
  end

  describe '#terms_to_entrylists' do
    let!(:dictionary) { FactoryGirl.create(:dictionary, title: 'qald-sider') }
    let(:text_annotator) { TextAnnotator.new(dictionary.title, current_user) }
    let(:user_id) { 1 }
    let(:pgr) { POSTGRESQL_RETRIEVER.new(dictionary.title, user_id) }
    before { 
      text_annotator.instance_variable_set(:@pgr, pgr)
    }
    let(:terms) {['term_1', 'term_2']}
    let(:opts) { {'threshold' => 5, 'top_n' => 10}}

    it { p text_annotator.terms_to_entrylists(terms, opts) }
  end
end
