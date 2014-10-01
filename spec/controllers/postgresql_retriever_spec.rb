# encoding: utf-8
require 'spec_helper'
require "#{ Rails.root }/app/controllers/text_annotator/retrieve_postgresql_db" 

describe POSTGRESQL_RETRIEVER do
  let(:dic_name) { 'dictionary title' }
  let(:user_id) { 1 }
  let(:pgr) { POSTGRESQL_RETRIEVER.new(dic_name, user_id) }
  # before { pgr.instance_variable_set(:@db, dictionaries: Dictionary, user_dictionaries: UserDictionary, entries: Entry, removed_entries: RemovedEntry, new_entries: NewEntry) }

  describe '#initialize' do
    it { expect(pgr.instance_variable_get(:@db)).to eql(ActiveRecord::Base) }

    it { expect(pgr.instance_variable_get(:@dic_name)).to eql(dic_name) }

    it { expect(pgr.instance_variable_get(:@user_id)).to eql(user_id) }

    it { expect(pgr.instance_variable_get(:@results_cache)).to be_blank }
  end

  describe '#dictionary_exist?' do
    context 'when dictionary where title == dic_name is not present' do
      it { expect(pgr.dictionary_exist?(dic_name)).to be_falsey }
    end

    context 'when dictionary where title == dic_name is present' do
      let!(:dictionary) { FactoryGirl.create(:dictionary, title: dic_name) }

      it { expect(pgr.dictionary_exist?(dic_name)).to be_truthy }
    end
  end

  describe '#get_string_normalization_options' do
    context 'when dic present' do
      let!(:dictionary) { FactoryGirl.create(:dictionary, title: dic_name, lowercased: false, hyphen_replaced: false, stemmed: false) }

      it { expect( pgr.get_string_normalization_options ).to eql({lowercased: dictionary.lowercased, hyphen_replaced: dictionary.hyphen_replaced, stemmed: dictionary.stemmed}) }
    end

    context 'when dic blank' do
      it { expect( pgr.get_string_normalization_options ).to be_blank }
    end
  end

  describe '#retrieve_similar_strings' do
    let(:simfun) { 5 }
    let(:threshold) { 0.01 }
    let(:query) { 'query' }
    context 'when basedic is present' do
      let!(:dictionary) { FactoryGirl.create(:dictionary, title: dic_name) }

      context 'when userdic is blank' do
        it { 
          NewEntry.should_not_receive(:select)
          pgr.retrieve_similar_strings(nil, 50)
        }

        it { expect( pgr.retrieve_similar_strings(nil, 50) ).to be_blank }
      end

      context 'when userdic is present' do
        let!(:user_dictionary) { FactoryGirl.create(:user_dictionary, dictionary_id: dictionary.id, user_id: user_id) }

        context 'when ds(new_entry where user_dictionary_id == userdic_id AND similarity >= threshold) present' do
          let!(:new_entry_1) { FactoryGirl.create(:new_entry, user_dictionary_id: user_dictionary.id, search_title: query)}
          let!(:new_entry_2) { FactoryGirl.create(:new_entry, user_dictionary_id: user_dictionary.id, search_title: "#{ query }-")}
          let!(:new_entry_3) { FactoryGirl.create(:new_entry, user_dictionary_id: user_dictionary.id, search_title: 's' )}

          it 'shoud return similar search_titles' do
            expect( pgr.retrieve_similar_strings(query, threshold) ).to match_array([new_entry_1.search_title, new_entry_2.search_title])
          end
        end

        context 'when ds(new_entry where user_dictionary_id == userdic_id AND similarity >= threshold) blank' do
          it { expect( pgr.retrieve_similar_strings(query, threshold) ).to be_blank }
        end
      end
    end

    context 'when basedic is blank' do
      it { 
        UserDictionary.should_not_receive(:select)
        pgr.retrieve_similar_strings(nil, 50)
      }

      it { 
        NewEntry.should_not_receive(:select)
        pgr.retrieve_similar_strings(nil, 50)
      }

      it { expect( pgr.retrieve_similar_strings(nil, 50) ).to be_blank }
    end
  end

  describe '#retrieve' do
    context 'when @results_cache include ann[:requested_query]' do
      let(:array_1) { 'array_1' }
      let(:array_2) { 'array_2' }
      let(:results_cache) { ['query'] }
      let(:get_from_cache) { [[array_1], array_2, []]  }
      let(:anns) { [{requested_query: results_cache[0], original_query: 'original_query', offset: 0, sim: 'sim'}] }
      before { 
        pgr.instance_variable_set(:@results_cache, results_cache)
        pgr.stub(:get_from_cache).and_return(get_from_cache)
      }

      it 'shoud return results from get_from_cache and delete blank array and flatten array' do 
        pgr.should_receive(:get_from_cache).with(anns[0][:requested_query], anns[0][:original_query], anns[0][:offset], anns[0][:sim])
        expect(pgr.retrieve(anns)).to eql([array_1, array_2])
      end
    end

    context 'when @results_cache not include ann[:requested_query]' do
      let(:array_3) { 'array_3' }
      let(:array_4) { 'array_4' }
      let(:search_db) { [[array_3], array_4, []]  }
      let(:anns) { [{requested_query: 'new query', original_query: 'original_query', offset: 0, sim: 'sim'}] }
      before { 
        pgr.instance_variable_set(:@results_cache, [])
        pgr.stub(:search_db).and_return(search_db)
      }

      it 'shoud return results from search_db and delete blank array and flatten array' do 
        pgr.should_receive(:search_db).with(anns[0][:requested_query], anns[0][:original_query], anns[0][:offset], anns[0][:sim])
        expect(pgr.retrieve(anns)).to eql([array_3, array_4])
      end
    end
  end

  describe '#get_from_cache' do
    let(:results_cache) { {'query' => [{uri: 'uri', label: 'label'}]} }
    let(:query) { 'query' }
    let(:ori_query) { 'ori_query' }
    let(:offset) { 'offset' }
    let(:sim) { 'sim' }
    let(:build_output) { 'build_output' }
    before { 
      pgr.instance_variable_set(:@results_cache, results_cache)
      pgr.stub(:build_output).and_return(build_output)
      pgr.should_receive(:build_output).with(query, ori_query, results_cache['query'][0], sim, offset)
    }

    it 'shoud return collect build_output results' do
      expect(pgr.get_from_cache(query, ori_query, offset, sim)).to eql([ build_output ])
    end
  end

  describe '#search_db' do
    let(:results_cache) { {'query' => [{uri: 'uri', label: 'label'}]} }
    let(:query) { 'query' }
    let(:ori_query) { 'ori_query' }
    let(:offset) { 'offset' }
    let(:sim) { 'sim' }
    let(:get_entries_from_db) { ['entry'] }
    let(:build_output) { 'build_output' }
    before { 
      pgr.instance_variable_set(:@results_cache, results_cache)
      pgr.stub(:get_entries_from_db).and_return(get_entries_from_db)
      pgr.stub(:build_output).and_return(build_output)
    }

    it { 
      pgr.should_receive(:get_entries_from_db).with(query, :search_title)
      pgr.search_db(query, ori_query, offset, sim)
    }

    it { 
      pgr.should_receive(:build_output).with(query, ori_query, get_entries_from_db[0], sim, offset)
      pgr.search_db(query, ori_query, offset, sim)
    }
    
    it 'shoud return collect build_output' do 
      expect( pgr.search_db(query, ori_query, offset, sim) ).to eql([build_output])
    end

    it 'shoud update @results_cache[query] by adding build_output' do
      pgr.search_db(query, ori_query, offset, sim)
      expect( pgr.instance_variable_get(:@results_cache)[query] ).to eql([build_output])
    end
  end
    
  describe '#get_entries_from_db' do
    context 'when dictionary where title == tittle blank' do
      it { 
        UserDictionary.should_not_receive(:select)
        pgr.get_entries_from_db(nil, nil) 
      }

      it { 
        RemovedEntry.should_not_receive(:select)
        pgr.get_entries_from_db(nil, nil) 
      }

      it { 
        NewEntry.should_not_receive(:where)
        pgr.get_entries_from_db(nil, nil) 
      }

      it { expect(pgr.get_entries_from_db(nil, nil)).to be_blank }
    end

    context 'when dictionary where title == tittle present' do
      let!(:dictionary) { FactoryGirl.create(:dictionary, title: dic_name) }

      context 'when user_dics is blank' do
        it { 
          RemovedEntry.should_not_receive(:select)
          pgr.get_entries_from_db('u.r.i', :uri)
        }

        it { 
          NewEntry.should_not_receive(:where)
          pgr.get_entries_from_db('u.r.i', :uri)
        }

        it { expect(pgr.get_entries_from_db('u.r.i', :uri)).to be_blank }
      end

      context 'when user_dics is present' do
        let!(:user_dictionary) { FactoryGirl.create(:user_dictionary, dictionary_id: dictionary.id, user_id: user_id) }

        context 'when removed_entry_idlist present' do
          let!(:entry_removed) { FactoryGirl.create(:entry, dictionary_id: dictionary.id, uri: query) }
          let!(:removed_entry) { FactoryGirl.create(:removed_entry, user_dictionary_id: user_dictionary.id, entry_id: entry_removed.id) }
          let(:query) {'uri'}

          context 'when ds(entries not included in removed_entry_idlist) is present' do
            let!(:entry_not_removed) { FactoryGirl.create(:entry, dictionary_id: dictionary.id, uri: query, label: 'not removed label', view_title: 'not removed view_title') }

            it 'should return hash from entries not included in removed_entry_idlist' do 
              expect(pgr.get_entries_from_db(query, :uri)).to eql(
                [{label: entry_not_removed[:label], uri: entry_not_removed[:uri], title: entry_not_removed[:view_title]}]
              )
            end 

            context 'when new_entries present' do
              let!(:new_entry) { FactoryGirl.create(:new_entry, user_dictionary_id: user_dictionary.id, uri: query) }

              it 'should return hash from entries not included in removed_entry_idlist and new_entries' do 
                expect(pgr.get_entries_from_db(query, :uri)).to eql(
                  [
                    {label: entry_not_removed[:label], uri: entry_not_removed[:uri], title: entry_not_removed[:view_title]},
                    {label: new_entry[:label], uri: new_entry[:uri], title: new_entry[:view_title]}
                  ]
                )
              end 
            end
          end

          context 'when ds(entries not included in removed_entry_idlist) is blank' do
            context 'when new_entries present' do
              let!(:new_entry) { FactoryGirl.create(:new_entry, user_dictionary_id: user_dictionary.id, uri: query) }

              it 'should return hash from new_entries' do 
                expect(pgr.get_entries_from_db(query, :uri)).to eql(
                  [
                    {label: new_entry[:label], uri: new_entry[:uri], title: new_entry[:view_title]}
                  ]
                )
              end 
            end 
          end
        end
      end
    end
  end

  describe 'build_output' do
    let(:arguments) { {query: 'query', ori_query: 'ori_query', res: {uri: 'res uri', label: 'res label'}, sim: 'sim', offset: 'offset'}} 

    it { expect( pgr.build_output(arguments[:query], arguments[:ori_query], arguments[:res], arguments[:sim], arguments[:offset]) ).to eql(
      {
        requested_query: arguments[:query], 
        original_query: arguments[:ori_query], 
        offset: arguments[:offset], 
        uri: arguments[:res][:uri], 
        label: arguments[:res][:label], 
        sim: arguments[:sim]}) }
  end
end
