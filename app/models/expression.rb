require 'elasticsearch/model'

class Expression < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  has_many :label_entries, :class_name => 'Entry', :as => :label, :dependent => :destroy
  has_many :uri_entries, :class_name => 'Entry', :as => :uri, :dependent => :destroy

  attr_accessible :value

  def as_indexed_json(options={})
    as_json(
      only: [:id, :words],
      include: [:uris, :expressions_uris]  
    )
  end

  def self.suggest_expression(arguments = {})
    operator = 'or'
    if arguments[:operator] == 'exact'
      operator = 'and' 
    end
    size = arguments[:size].to_i if arguments[:size].present?

    search(
      :min_score => 1,
      :size => 10,
      sort: [
        '_score'
      ],
      query: {
        match: {
          words: {
            query: arguments[:query],
            type: :phrase_prefix,
            operator: operator,
            fuzziness: 0
          }
        }
      }
    )
  end

  def self.search_fuzzy(arguments = {})
    arguments[:fuzziness] ||= 2
    # search(
    #   query: {
    #     multi_match: {
    #       fields: [:words],
    #       query: query,
    #       fuzziness: 2
    #     }
    #   }
    # )
    # OR search if query include comma
    arguments[:query] = arguments[:query].split(',') if arguments[:query] =~ /\,/
    search(
      query: {
        match: {
          words:{
            query: arguments[:query],
            fuzziness: arguments[:fuzziness]
          }
        }
      }
    )
  end

  def dictionary_uri(dictionary_id)
    if uris.present?
      uris.where(['expressions_uris.dictionary_id = ?', dictionary_id]).first 
    end
  end
end
