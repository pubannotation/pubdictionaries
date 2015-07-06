require 'elasticsearch/model'

class Expression < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  has_and_belongs_to_many :uris
  has_many :expressions_uris
  # count up/down dictionaries_count when save/destroy entries_uri
  has_many :dictionaries, through: :expressions_uris

  scope :diff, where(['created_at > ?', 1.hour.ago])
  attr_accessible :words

  scope :dictionary, lambda{|dictionary_id|
    joins(:expressions_uris).where('expressions_uris.dictionary_id = ?', dictionary_id)
  }

  def as_indexed_json(options={})
    as_json(
      only: [:id, :words],
      include: [:uris, :expressions_uris]  
    )
  end

  def self.search_fuzzy(query)
    search(
      query: {
        multi_match: {
          fields: [:words],
          query: query,
          fuzziness: 2
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
