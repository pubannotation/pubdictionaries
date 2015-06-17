require 'elasticsearch/model'

class Entry < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  settings analysis: {
    tokenizer: {
      ngram_tokenizer: {
        type: "nGram",
        min_gram: "2",
        max_gram: "3",
        token_chars: [ "letter", "digit" ]
      }
    },
    analyzer: {
      ngram_analyzer: {
        tokenizer: "ngram_tokenizer"
      }
    }
  }

  def self.search_ngram(query)
    search(
      settings: {
        analysis: {
          analyzer:{
            my_ngram_analyser: {
              tokenizer: 'my_ngram_analyser'
            }
          },
          tokenizer: {
            my_ngram_tokenizer: {
              type: 'nGram',
              min_gram: 1,
              max_gram: 5,
              token_chars: [ "letter", "digit" ]
            }
          }
        }
      },
      size: 1000
    )

  end

  def self.search_suggest(query)
    search(
      suggest: {
        text: query,
        simple_phrase: {
          phrase: {
            field: view_title,
            size: 1
          }
        }
      },
      size: 1000
    )
  end

  def self.search_more_like_this(query)
    search(
      query: {
        more_like_this: {
          fields: [:view_title],
          like_text: query,
          min_term_freq: 1,
          max_query_terms: 5
        }
      }
    )
  end

  def self.search_fuzzy(query)
    search(
      query: {
        multi_match: {
          fields: [:view_title, :search_title],
          query: query,
          fuzziness: 2
        }
      }
    )
  end
  
  attr_accessible :uri, :label, :view_title, :search_title
  belongs_to :dictionary

  validates :uri, :view_title, :search_title, :presence => true

  # Return a list of entries except the ones specified by skip_ids.
  def self.get_remained_entries(skip_ids = [])
    if skip_ids.empty?
      # Return the entries of the current dictionary.
      self.scoped 
    else
      # id not in () not work if () is empty.
      where("id not in (?)", skip_ids) 
    end
  end

  def self.get_disabled_entries(skip_ids)
    where(:id => skip_ids)
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end


end
