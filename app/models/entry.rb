class Entry < ActiveRecord::Base
  include Elasticsearch::Model
  # include Elasticsearch::Model::Callbacks

  settings index: {
    analysis: {
      analyzer: {
        tokenization: { # typographic normalization _ morphosyntactic normalization 
          tokenizer: :standard,
          filter: [:standard, :asciifolding, :lowercase, :snowball_en]
        },
        normalization1: { # typographic normalization
          tokenizer: :standard,
          filter: [:standard, :asciifolding, :lowercase]
        },
        normalization2: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :standard,
          filter: [:standard, :asciifolding, :lowercase, :snowball_en, :extended_stop]
        },
        ngrams: {
          tokenizer: :trigram,
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
      indexes :label, type: :string, analyzer: :ngrams, index_options: :docs, norms: {enabled: false}
      indexes :norm1, type: :string, analyzer: :ngrams, index_options: :docs, norms: {enabled: false}
      indexes :norm2, type: :string, analyzer: :ngrams, index_options: :docs, norms: {enabled: false}
      indexes :label_length, type: :integer
      indexes :norm1_length, type: :integer
      indexes :norm2_length, type: :integer
      indexes :identifier, type: :string, index: :not_analyzed
      indexes :entries_dictionaries do
        indexes :id, type: :long
      end
    end
  end

  attr_accessible :label, :identifier, :dictionaries_num, :flag
  attr_accessible :norm1, :norm2
  attr_accessible :label_length, :norm1_length, :norm2_length

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
    return nil if items[0].length < 2 || items[0].length > 64
    return nil if items[0].empty? || items[1].empty?

    return nil if items[1].length > 255

    [items[0], items[1]]
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

  def as_indexed_json(options={})
    as_json(
      only: [:id, :label, :norm1, :norm2, :label_length, :norm1_length, :norm2_length, :identifier],
      include: {dictionaries: {only: :id}}
    )
  end

  def self.search_as_text(label, dictionary = nil, page)
    norm1 = Entry.normalize1(label)
    norm2 = Entry.normalize2(label)
    lquery  = get_ngrams(label).map{|n| {constant_score: {query: {term: {label: {value: n}}}}} }
    n1query = get_ngrams(norm1).map{|n| {constant_score: {query: {term: {norm1: {value: n}}}}} }
    n2query = get_ngrams(norm2).map{|n| {constant_score: {query: {term: {norm2: {value: n}}}}} }
    self.__elasticsearch__.search(
      query: {
        bool: {
          should: [
            {
              function_score: {
                query: {
                  bool: {
                    should: lquery
                  }
                },
                field_value_factor: {
                  field: :label_length,
                  modifier: :reciprocal
                }
              }
            },
            {
              function_score: {
                query: {
                  bool: {
                    should: n1query
                  }
                },
                field_value_factor: {
                  field: :norm1_length,
                  modifier: :reciprocal
                }
              }
            },
            {
              function_score: {
                query: {
                  bool: {
                    should: n2query
                  }
                },
                field_value_factor: {
                  field: :norm2_length,
                  modifier: :reciprocal
                },
                boost: 5
              }
            }
          ],
          filter: {terms: {"dictionaries.id" => [dictionary.id]}}
        }
      }
    ).page(page)
  end

  def self.search_as_term(label, norm1, norm2, dictionaries = [])
    return [] if norm2.empty?
    lquery  = get_ngrams(label).map{|n| {constant_score: {query: {term: {label: {value: n}}}}} }
    n1query = get_ngrams(norm1).map{|n| {constant_score: {query: {term: {norm1: {value: n}}}}} }
    n2query = get_ngrams(norm2).map{|n| {constant_score: {query: {term: {norm2: {value: n}}}}} }
    self.__elasticsearch__.search(
      query: {
        bool: {
          should: [
            {
              function_score: {
                query: {
                  bool: {
                    should: lquery
                  }
                },
                field_value_factor: {
                  field: :label_length,
                  modifier: :reciprocal
                }
              }
            },
            {
              function_score: {
                query: {
                  bool: {
                    should: n1query
                  }
                },
                field_value_factor: {
                  field: :norm1_length,
                  modifier: :reciprocal
                }
              }
            },
            {
              function_score: {
                query: {
                  bool: {
                    should: n2query
                  }
                },
                field_value_factor: {
                  field: :norm2_length,
                  modifier: :reciprocal
                },
                boost: 5
              }
            }
          ],
          filter: [
            {range: {norm2_length: {"lte" => norm2.length + 10}}},
            {terms: {"dictionaries.id" => dictionaries}}
          ]
        }
      }
    ).results
  end

  def self.search_by_term(term, dictionaries, threshold)
    norm1 = Entry.normalize1(term)
    norm2 = Entry.normalize2(term)
    entries = Entry.search_as_term(term, norm1, norm2, dictionaries)
    entries = entries.collect{|r| {id: r.id, label: r.label, identifier:r.identifier, norm1: r.norm1, norm2: r.norm2}}
    entries.collect!{|entry| entry.merge(score: str_cosine_sim(term, norm1, norm2, entry[:label], entry[:norm1], entry[:norm2]))}.delete_if{|entry| entry[:score] < threshold}
    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_as_prefix(label, dictionaries = [])
    norm2 = Entry.normalize2(label)
    n2query = get_ngrams(norm2).map{|n| {constant_score: {query: {term: {norm2: {value: n}}}}} }
    self.__elasticsearch__.search(
      min_score: 1.5,
      size: 0,
      terminate_after: 1,
      query: {
        bool: {
          should: [
            {
              function_score: {
                query: {
                  bool: {
                    should: n2query
                  }
                }
              }
            }
          ],
          filter: [
            {terms: {"dictionaries.id" => dictionaries}}
          ]
        }
      }
    )
  end


  def self.search_as_prefix0(norm, dictionaries = [])
    self.__elasticsearch__.search(
      size: 0,
      terminate_after: 1,
      query: {
        bool: {
          must: [
            {
              match: {
                norm: {
                  query: norm,
                }
              }
            }
          ],
          filter: [
            {terms: {"dictionaries.id" => dictionaries}}
          ]
        }
      }
    ).results.total
  end

  # Compute similarity of two strings
  #
  # * (string) string1
  # * (string) string2
  #
  def self.str_cosine_sim(str1, s1norm1, s1norm2, str2, s2norm1, s2norm2)
    str1_trigrams = []; str1.split('').each_cons(2){|a| str1_trigrams << a};
    str2_trigrams = []; str2.split('').each_cons(2){|a| str2_trigrams << a};
    s1norm1_trigrams = []; s1norm1.split('').each_cons(2){|a| s1norm1_trigrams << a};
    s1norm2_trigrams = []; s1norm2.split('').each_cons(2){|a| s1norm2_trigrams << a};
    s2norm1_trigrams = []; s2norm1.split('').each_cons(2){|a| s2norm1_trigrams << a};
    s2norm2_trigrams = []; s2norm2.split('').each_cons(2){|a| s2norm2_trigrams << a};
    (jaccard_sim(str1_trigrams, str2_trigrams) + jaccard_sim(s1norm1_trigrams, s2norm1_trigrams) + 5 * jaccard_sim(s1norm2_trigrams, s2norm2_trigrams)) / 7
  end

  # Compute cosine similarity of two vectors
  #
  # * (array) items1
  # * (array) items2
  #
  def self.cosine_sim(items1, items2)
    (items1 & items2).size.to_f / Math.sqrt(items1.size * items2.size)
  end

  # Compute jaccard similarity of two sets
  #
  # * (array) items1
  # * (array) items2
  #
  def self.jaccard_sim(items1, items2)
    (items1 & items2).size.to_f / (items1 | items2).size
  end


  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Get the ngrams of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.get_ngrams(text)
    return [] if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=ngrams', text.gsub('{', '\{').sub(/^-/, '\-')), symbolize_names: true)[:tokens].map{|t| t[:token]}
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize1(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=normalization1', text.sub(/^-/, '\-').gsub('{', '\{')), symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize2(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=normalization2', text.sub(/^-/, '\-').gsub('{', '\{')), symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end


  # Tokenize an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=tokenization', text.sub(/^-/, '\-').gsub('{', '\{')), symbolize_names: true)[:tokens]
  end

  def destroy
    self.__elasticsearch__.delete_document
    super
  end
end
