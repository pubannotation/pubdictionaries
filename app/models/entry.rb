class Entry < ActiveRecord::Base
  include Elasticsearch::Model
  # include Elasticsearch::Model::Callbacks

  settings index: {
    analysis: {
      analyzer: {
        standard_normalization: {
          tokenizer: :standard,
          filter: [:standard, :extended_stop, :asciifolding, :kstem]
        }
      },
      filter: {
        extended_stop: {
          type: :stop,
          stopwords: ["_english_", "unspecified"]
        }
      }
    }
  } do
    mappings do
      indexes :label, type: :string, index: :not_analyzed
      indexes :norm, type: :string, analyzer: :standard_normalization, index_options: :docs
      indexes :norm_length, type: :integer
      indexes :identifier, type: :string, index: :not_analyzed
      indexes :entries_dictionaries do
        indexes :id, type: :long
      end
    end
  end

  attr_accessible :label, :identifier, :dictionaries_num, :flag
  attr_accessible :norm, :norm_length

  has_many :membership
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

  def self.get_by_value(label, identifier)
    self.find_by_label_and_identifier(label, identifier)
  end

  def self.read_entry_line(line)
    line.strip!

    return nil if line == ''
    return nil if line.start_with? '#'

    items = line.split(/\t/)
    return nil if items.size < 2
    return nil if items[0].length < 2 || items[0].length > 64
    return nil if items[0].empty? || items[1].empty?

    [items[0], items[1]]
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

  def as_indexed_json(options={})
    as_json(
      only: [:id, :label, :norm, :norm_length, :identifier],
      include: {dictionaries: {only: :id}}
    )
  end

  def self.search_as_text(keywords, dictionary = nil, page)
    self.__elasticsearch__.search(
      query: {
        filtered: {
          query: {
            match: {
              norm: {
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
    ).page(page)
  end

  def self.es_search_as_term(term, tokens, dictionaries = [])
    self.__elasticsearch__.search(
      min_score: 0.2,
      query: {
        bool: {
          must: {
            match: {
              norm: {
                query: term,
                operator: "and",
                fuzziness: "AUTO"
              }
            }
          },
          filter: [
            {range: {norm_length: {"lte" => tokens.length + 1}}},
            {terms: {"dictionaries.id" => dictionaries}}
          ]
        }
      }
    )
  end

  def self.search_by_term(term, term_tokens, dictionaries, threshold)
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
  def self.cosine_sim(string_tokens, label_tokens)
    # extraploate tokens with bigrams
    # bigrams = []; tokens1.each_cons(2){|a| bigrams << a}; tokens1 += bigrams
    # bigrams = []; tokens2.each_cons(2){|a| bigrams << a}; tokens2 += bigrams
    return (string_tokens & label_tokens).size.to_f / Math.sqrt(string_tokens.size * label_tokens.size)
  end

  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Tokenize an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/entries/_analyze?analyzer=standard_normalization', text), symbolize_names: true)[:tokens]
  end

end
