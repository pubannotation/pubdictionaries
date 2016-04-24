class Label < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

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
      indexes :value, type: :string, analyzer: :standard_normalization, index_options: :docs
      indexes :terms, type: :string, index: :not_analyzed
      indexes :terms_length, type: :integer
      indexes :labels_dictionaries do
        indexes :id, type: :long
      end
    end
  end

  has_many :entries
  has_many :dictionaries, :through => :entries

  attr_accessible :value, :terms, :terms_length

  scope :diff, where(['created_at > ?', 2.hour.ago])
  scope :added_after, -> (time) {where('created_at > ?', time)}

  def self.get_by_value(value)
    value = Label.uncapitalize(value)
    label = self.find_by_value(value)
    if label.nil?
      terms = tokenize(value).collect{|t| t[:token]}
      label = self.new({value: value, terms: terms.join("\t"), terms_length: terms.length})
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
      only: [:id, :value, :terms, :terms_length],
      include: {dictionaries: {only: :id}}
    )
  end

  def self.search_as_text(keywords, dictionary = nil, page)
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
    ).page(page)
  end

  def self.search_as_term(label, terms, dictionaries = [])
    self.__elasticsearch__.search(
      min_score: 0.8,
      query: {
        bool: {
          must: {
            match: {
              value: {
                query: label,
                operator: "and",
                fuzziness: "AUTO"
              }
            }
          },
          filter: [
            {range: {terms_length: {"lte" => terms.length + 1}}},
            {terms: {"dictionaries.id" => dictionaries}}
          ]
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

  def self.find_similar_labels(string, string_tokens, dictionaries, threshold, rich)
    es_results = Label.search_as_term(string, string_tokens, dictionaries).results
    labels = es_results.collect{|r| {label: r.value, id: r.id, terms: r.terms.split(/\t/)}}
    labels = labels.collect{|label| label.merge(score: cosine_sim(string_tokens, label[:terms]))}.delete_if{|label| label[:score] < threshold}
    labels = labels.collect{|label| label[:label]} unless rich
    {es_results: es_results.total, labels: labels}
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

  def self.uncapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Tokenize an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/labels/_analyze?analyzer=standard_normalization', text), symbolize_names: true)[:tokens]
  end

  def self.get_term_vector(label_id)
    (JSON.parse RestClient.get("http://localhost:9200/labels/label/#{label_id}/_termvector"))["term_vectors"]["value"]["terms"].keys
  end
end
