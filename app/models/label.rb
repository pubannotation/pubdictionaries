require 'elasticsearch/model'

class Label < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  settings index: {
    analysis: {
      filter: {
        snowball_en: {
          type: :snowball,
          language: "English"
        },
        asciifolding_preserve: {
          type: :asciifolding,
          preserve_original: true
        }
      },
      analyzer: {
        standard_english: {
          tokenizer: :standard,
          filter: [:standard, :lowercase, :asciifolding_preserve, :snowball_en]
        }
      }
    }
  } do
    mappings do
      indexes :value, analyzer: :standard_english
      indexes :labels_dictionaries do
        indexes :id, type: :long
      end
    end
  end

  has_many :entries, :dependent => :destroy
  has_many :dictionaries, :through => :entries

  attr_accessible :value

  scope :diff, where(['created_at > ?', 1.hour.ago])

  def self.get_by_value(value)
    label = self.find_by_value(value)
    if label.nil?
      label = self.new({value: value})
      label.save
    end
    label
  end

  def entries_count_up
    increment!(:entries_count)
  end

  def entries_count_down
    decrement!(:entries_count)
    destroy if entries_count == 0
  end

  def as_indexed_json(options={})
    as_json(
      only: [:id, :value],
      include: {dictionaries: {only: :id}}
    )
  end

  def self.search_as_text(keywords, dictionary = nil)
    self.__elasticsearch__.search(
      query: {
        filtered: {
          query: {
            match: {
              value: {
                query: keywords,
                operator: "and",
                fuzziness: "AUTO"
              }
            }
          },
          filter: {
            terms: {
              "dictionaries.id" => [dictionary.id]
            }
          }
        }
      }
    )
  end

  def self.search_as_term(keywords, dictionary = nil)
    self.__elasticsearch__.search(
      min_score: 0.8,
      query: {
        filtered: {
          query: {
            match: {
              value: {
                query: keywords,
                operator: "and",
                fuzziness: "AUTO"
              }
            }
          },
          filter: {
            terms: {
              "dictionaries.id" => [dictionary.id]
            }
          }
        }
      }
    )
  end

  def self.suggest(arguments = {})
    operator = 'or'
    if arguments[:operator] == 'exact'
      operator = 'and' 
    end
    size = arguments[:size].to_i if arguments[:size].present?

    self.__elasticsearch__.search(
      min_score: 1,
      size: 10,
      sort: [
        '_score'
      ],
      query: {
        match: {
          value: {
            query: arguments[:query],
            type: :phrase_prefix,
            operator: operator,
            fuzziness: 0
          }
        }
      }
    )
  end

end
