require 'elasticsearch/model'

class Uri < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  attr_accessible :resource

  has_and_belongs_to_many :expressions
  has_many :expressions_uris
  # count up/down dictionaries_count when save/destroy entries_uri
  has_many :dictionaries, through: :expressions_uris

  scope :diff, where(['created_at > ?', 1.day.ago])
  scope :dictionary, lambda{|dictionary_id|
    joins(:expressions_uris).where('expressions_uris.dictionary_id = ?', dictionary_id)
  }
  scope :dictionary_expression, lambda{|dictionary_id, expression_id|
    joins(:expressions_uris).where('expressions_uris.dictionary_id = ? AND expressions_uris.expression_id = ?', dictionary_id, expression_id)
  }

  def as_indexed_json(options={})
    as_json(
      only: [:id, :resource],
      include: [:expressions, :expressions_uris]  
    )
  end

  def self.search_fuzzy(query)
    search(
      query: {
        multi_match: {
          fields: [:resource],
          query: query,
          fuzziness: 2
        }
      }
    )
  end
end
