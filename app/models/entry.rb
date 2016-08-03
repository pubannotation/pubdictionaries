class Entry < ActiveRecord::Base
  include Elasticsearch::Model
  # include Elasticsearch::Model::Callbacks

  settings index: {
    analysis: {
      analyzer: {
        normalization: {
          tokenizer: :standard,
          filter: [:standard, :asciifolding, :lowercase, :extended_stop, :snowball_en]
        },
        ngrams: {
          tokenizer: :trigram,
          filter: [:standard, :asciifolding]
        },
        tokenization: {
          tokenizer: :standard,
          filter: [:standard, :asciifolding]
        }
      },
      filter: {
        snowball_en: {
          type: :snowball,
          language: :english
        },
        extended_stop: {
          type: :stop,
          stopwords: ["_english_", "unspecified"]
        }
      },
      tokenizer: {
        trigram: {
          type: :ngram,
          min_gram: 3,
          max_gram: 3
        }
      }
    }
  } do
    mappings do
      indexes :label, type: :string, analyzer: :ngrams, index_options: :docs
      indexes :norm, type: :string, analyzer: :ngrams, index_options: :docs
      indexes :norm_length, type: :integer
      indexes :length_factor, type: :integer
      indexes :identifier, type: :string, index: :not_analyzed
      indexes :entries_dictionaries do
        indexes :id, type: :long
      end
    end
  end

  attr_accessible :label, :identifier, :dictionaries_num, :flag
  attr_accessible :norm, :norm_length, :length_factor

  has_many :membership, :dependent => :destroy
  has_many :dictionaries, :through => :membership

  validates :label, presence: true
  validates :identifier, presence: true

  def self.as_tsv
    column_names = %w{label identifier}

    CSV.generate(col_sep: "\t") do |tsv|
      tsv << [:label, :id]
      all.each do |entry|
        tsv << [entry.label, entry.identifier]
      end
    end
  end

  scope :updated, where("updated_at > ?", 1.seconds.ago)

  def self.get_by_value(label, identifier)
    self.find_by_label_and_identifier(label, identifier)
  end

  def self.find_by_identifier(identifier, dictionary)
    dictionary.nil? ? dictionary.entries.where(identifier:identifier) : self.where(identifier:identifier)
  end

  def self.read_entry_line(line)
    line.strip!

    return nil if line == ''
    return nil if line.start_with? '#'

    items = line.split(/\t/)
    return nil if items.size < 2
    return nil if items[0].length < 2 || items[0].length > 32
    return nil if items[0].empty? || items[1].empty?

    return nil if items[1].length > 255

    [items[0], items[1]]
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

  def as_indexed_json(options={})
    as_json(
      only: [:id, :label, :norm, :norm_length, :length_factor, :identifier],
      include: {dictionaries: {only: :id}}
    )
  end

  def self.search_as_text(text, dictionary = nil, page)
    norm = Entry.normalize(text)
    self.__elasticsearch__.search(
      query: {
        function_score: {
          query: {
            bool: {
              must: [
                {
                  match: {
                    label: {
                      query: text
                    }
                  }
                },
                {
                  match: {
                    norm: {
                      query: norm,
                      boost: 50
                    }
                  }
                }
              ],
              filter: {
                terms: {
                  "dictionaries.id" => [dictionary.id]
                }
              }
            }
          },
          field_value_factor: {
            field: :length_factor,
            modifier: :reciprocal
          }
        }
      }
    ).page(page)
  end

  def self.es_search_as_term(term, norm, dictionaries = [])
    self.__elasticsearch__.search(
      min_score: 0.015,
      query: {
        function_score: {
          query: {
            bool: {
              must: [
                {
                  match: {
                    label: {
                      query: term
                    }
                  }
                },
                {
                  match: {
                    norm: {
                      query: norm,
                      boost: 50
                    }
                  }
                }
              ],
              filter: [
                {range: {norm_length: {"lte" => norm.length + 2}}},
                {terms: {"dictionaries.id" => dictionaries}}
              ]
            }
          },
          field_value_factor: {
            field: :length_factor,
            modifier: :reciprocal
          }
        }
      }
    )
  end

  def self.search_by_term(term, dictionaries, threshold)
    norm = Entry.normalize(term)
    es_results = Entry.es_search_as_term(term, norm, dictionaries).results
    entries = es_results.collect{|r| {id: r.id, label: r.label, identifier:r.identifier, norm: r.norm}}
    entries.collect!{|entry| entry.merge(score: str_cosine_sim(term, norm, entry[:label], entry[:norm]))}.delete_if{|entry| entry[:score] < threshold}
    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_by_nterm(term, term_tokens, dictionaries, threshold)
    es_results = Entry.es_search_as_term(term, term_tokens, dictionaries).results
    entries = es_results.collect{|r| {id: r.id, label: r.label, identifier:r.identifier, tokens: r.norm.split(/\t/)}}
    entries.collect!{|entry| entry.merge(score: cosine_sim(term_tokens, entry[:tokens]))}.delete_if{|entry| entry[:score] < threshold}
    entries
  end

  # Compute similarity of two strings
  #
  # * (string) string1
  # * (string) string2
  #
  def self.str_cosine_sim(str1, norm1, str2, norm2)
    str1_trigrams = []; str1.split('').each_cons(2){|a| str1_trigrams << a};
    str2_trigrams = []; str2.split('').each_cons(2){|a| str2_trigrams << a};
    norm1_trigrams = []; norm1.split('').each_cons(2){|a| norm1_trigrams << a};
    norm2_trigrams = []; norm2.split('').each_cons(2){|a| norm2_trigrams << a};
    (cosine_sim(str1_trigrams, str2_trigrams) + 2 * cosine_sim(norm1_trigrams, norm2_trigrams)) / 3
  end

  # Compute similarity of two strings
  #
  # * (array) items1
  # * (array) items2
  #
  def self.cosine_sim(items1, items2)
    return (items1 & items2).size.to_f / Math.sqrt(items1.size * items2.size)
  end

  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Get the ngrams of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.get_ngrams(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=ngrams', text.gsub('{', '\{').sub(/^-/, '\-')), symbolize_names: true)[:tokens].map{|t| t[:token]}
  end

  # Get the ngrams of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=normalization', text.sub(/^-/, '\-').gsub('{', '\{')), symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end

  # Tokenize an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=tokenization', text.gsub('{', '\{').sub(/^-/, '\-')), symbolize_names: true)[:tokens]
  end

  def destroy
    self.__elasticsearch__.delete_document
    super
  end
end
