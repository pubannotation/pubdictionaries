require 'elasticsearch/model'

class NewEntry < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  # settings analysis: {
  #   tokenizer: {
  #     ngram_tokenizer: {
  #       type: "nGram",
  #       min_gram: 1,
  #       max_gram: 50,
  #       token_chars: [ "letter", "digit" ]
  #     }
  #   },
  #   analyzer: {
  #     ngram_analyzer: {
  #       tokenizer: "ngram_tokenizer"
  #     }
  #   }
  # }

  def self.search_suggest(query)
    search(
    suggest: {
      text: query
    }
    )#.collect{|n| n.view_title}.uniq
  end

  def self.search_test(query)
    search(query).records.collect{|new_entry| new_entry.view_title }.uniq
  end

  def self.search_more_like_this(query)
    search(query: {
      more_like_this: {
        fields: [:view_title],
        like_text: query,
        min_term_freq: 1,
        max_query_terms: 5
      }
    })#.collect{|n| n.view_title}.uniq
  end

  def self.search_ngram(query)
    search(query: {
      more_like_this: {
        fields: [:view_title],
        like_text: query,
        min_term_freq: 1,
        max_query_terms: 5
      }
    }).collect{|n| n.view_title}.uniq
  end

  def self.search_fuzzy(query)
    # fuzzy search does not list all records
    search( query: {
      multi_match: {
        fields: [:view_title, :search_title],
        query: query,
        fuzziness: 1
      }
    }).records.collect{|n| n.view_title}.uniq
  end

  def self.search_similar(query)
    search(similarity: {
      my_similarity: {
      }
    },
    query: {
      more_like_this: {
        fields: [:view_title],
        like_text: query,
        min_term_freq: 1,
        max_query_terms: 5
      }
    }).collect{|n| n.view_title}.uniq
  end

  mappings do
    indexes :id, type: :long, index: :not_analyzed
    indexes :label, type: :string, index: :not_analyzed
    indexes :uri, type: :string, index: :not_analyzed
    indexes :search_title, type: :string, index: :not_analyzed
    indexes :user_dictionary_id, type: :long, index: :not_analyzed
    indexes :created_at, type: :date, index: :not_analyzed
    indexes :updated_at, type: :date, index: :not_analyzed

    indexes :view_title, type: :string, index: :analyzed, analyzer: :ngram_analyzer
    indexes :description, type: :string, index: :analyzed, analyzer: :ngram_analyzer
  end

  attr_accessible :label, :view_title, :search_title, :uri

  belongs_to :user_dictionary, :touch => true

  validates :view_title, :search_title, :uri, :presence => true

  def self.get_new_entries()
    self.scoped
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

end
