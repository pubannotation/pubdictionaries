require 'simstring'
require 'pp'

class Entry < ActiveRecord::Base
  MODE_NORMAL   = 0
  MODE_ADDITION = 1
  MODE_DELETION = 2

  include Elasticsearch::Model
  # include Elasticsearch::Model::Callbacks

  settings index: {
    analysis: {
      filter: {
        english_stop: {
          type: :stop,
          stopwords: [
            # "a",
            "an", "and", "are", "as", "at", "be", "but", "by", "for", "if", "in", "into", "is", "it",
            "no", "not", "of", "on", "or", "such", "that", "the", "their", "then", "there", "these",
            "they", "this", "to", "was", "will", "with"
          ]
        }
      },
      analyzer: {
        tokenization: { # typographic normalization
          tokenizer: :standard,
          filter: [:icu_folding]
        },
        normalization1: { # typographic normalization
          tokenizer: :standard,
          filter: [:icu_folding]
        },
        normalization2: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :standard,
          filter: [:icu_folding, :snowball, :english_stop]
        },
        ngrams: {
          tokenizer: :trigram,
          filter: [:standard, :asciifolding]
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
  }

  belongs_to :dictionary

  attr_accessible :id
  attr_accessible :label, :identifier
  attr_accessible :norm1, :norm2
  attr_accessible :label_length
  attr_accessible :mode
  attr_accessible :dictionary_id

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

  def as_indexed_json(options={})
    as_json(
      only: [:id, :label, :norm1, :norm2, :label_length, :norm1_length, :norm2_length, :identifier],
      include: {dictionaries: {only: :id}}
    )
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
    return nil if items[0].length < 2 || items[0].length > 127
    return nil if items[0].empty? || items[1].empty?

    return nil if items[1].length > 255

    [items[0], items[1]]
  end

  # def self.none
  #   where(:id => nil).where("id IS NOT ?", nil)
  # end

  def self.narrow_by_label_prefix(str, dictionary = nil, page = 0)
    norm1 = Entry.normalize1(str)
    dictionary.nil? ?
      self.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page) :
      dictionary.entries.where("norm1 LIKE ?", "#{norm1}%").order(:label_length).page(page)
  end

  def self.narrow_by_label(str, dictionary = nil, page = 0)
    norm1 = Entry.normalize1(str)
    dictionary.nil? ?
      self.where("norm1 LIKE ?", "%#{norm1}%").order(:label_length).page(page) :
      dictionary.entries.where("norm1 LIKE ?", "%#{norm1}%").order(:label_length).page(page)
  end

  def self.narrow_by_identifier(str, dictionary = nil, page = 0)
    dictionary.nil? ?
      self.where("identifier ILIKE ?", "%#{str}%").page(page) :
      dictionary.entries.where("identifier ILIKE ?", "%#{str}%").page(page)
  end

  def self.search_term(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
    return [] if term.empty?
    norm1 = Entry.normalize1(term) if norm1.nil?
    norm2 = Entry.normalize2(term) if norm2.nil?

    entries = dictionaries.inject([]) do |a1, dic|
      norm2s = ssdbs[dic.name].retrieve(norm2) if ssdbs[dic.name]
      a1 += norm2s.inject([]){|a2, norm2| a2 + dic.entries.where(norm2:norm2, mode:Entry::MODE_NORMAL)} if norm2s
      a1 += dic.entries.where(mode:Entry::MODE_ADDITION)
    end

    entries.map!{|e| {id: e.id, label: e.label, identifier:e.identifier, norm1: e.norm1, norm2: e.norm2}}.uniq!
    entries.map!{|e| e.merge(score: str_jaccard_sim(term, norm1, norm2, e[:label], e[:norm1], e[:norm2]))}.delete_if{|e| e[:score] < threshold}
    entries.sort_by{|e| e[:score]}.reverse
  end

  # Compute similarity of two strings
  #
  # * (string) string1
  # * (string) string2
  #
  def self.str_jaccard_sim(str1, s1norm1, s1norm2, str2, s2norm1, s2norm2)
    str1_trigrams = []; str1.split('').each_cons(2){|a| str1_trigrams << a};
    str2_trigrams = []; str2.split('').each_cons(2){|a| str2_trigrams << a};
    s1norm1_trigrams = []; s1norm1.split('').each_cons(2){|a| s1norm1_trigrams << a};
    s1norm2_trigrams = []; s1norm2.split('').each_cons(2){|a| s1norm2_trigrams << a};
    s2norm1_trigrams = []; s2norm1.split('').each_cons(2){|a| s2norm1_trigrams << a};
    s2norm2_trigrams = []; s2norm2.split('').each_cons(2){|a| s2norm2_trigrams << a};
    if s1norm2.empty? && s2norm2.empty?
      (jaccard_sim(str1_trigrams, str2_trigrams) + jaccard_sim(s1norm1_trigrams, s2norm1_trigrams)) / 2
    else
      (jaccard_sim(str1_trigrams, str2_trigrams) + jaccard_sim(s1norm1_trigrams, s2norm1_trigrams) + 10 * jaccard_sim(s1norm2_trigrams, s2norm2_trigrams)) / 12
    end
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
    return 0.0 if items1.empty? || items2.empty?
    (items1 & items2).size.to_f / (items1 | items2).size
  end


  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize1(text, normalizer = nil)
    raise ArgumentError, "Empty text" if text.empty?
    _text = text.tr('{}', '()')
    res = if normalizer.nil?
      http = Net::HTTP.new('localhost', 9200)
      http.request_post('/entries/_analyze?analyzer=normalization1', _text)
    else
      normalizer[:post].body = _text
      normalizer[:http].request(normalizer[:uri], normalizer[:post])
    end
    (JSON.parse res.body, symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize2(text, normalizer = nil)
    raise ArgumentError, "Empty text" if text.empty?
    _text = text.tr('{}', '()')
    res = if normalizer.nil?
      http = Net::HTTP.new('localhost', 9200)
      http.request_post('/entries/_analyze?analyzer=normalization2', _text)
    else
      normalizer[:post].body = _text
      normalizer[:http].request(normalizer[:uri], normalizer[:post])
    end
    (JSON.parse res.body, symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end

end
