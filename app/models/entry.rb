class Entry < ApplicationRecord
  MODE_NORMAL   = 0
  MODE_ADDITION = 1
  MODE_DELETION = 2

  include Elasticsearch::Model

  settings index: {
    analysis: {
      filter: {
        english_stop: {
          type: :stop,
          # 'an' is removed from the stopwords list for "ANS disease"
          stopwords: %w(and are as at be but by for if in into is it no not of on or such that the their then there these they this to was will with)
        }
      },
      analyzer: {
        tokenization: { # typographic normalization
          tokenizer: :nori_tokenizer,
          filter: [:icu_folding]
        },
        normalization1: { # typographic normalization
          tokenizer: :nori_tokenizer,
          filter: [:icu_folding]
        },
        normalization2: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :nori_tokenizer,
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

  validates :label, presence: true
  validates :identifier, presence: true

  def self.as_tsv
    CSV.generate(col_sep: "\t") do |tsv|
      tsv << [:label, :id]
      all.each do |entry|
        tsv << [entry.label, entry.identifier]
      end
    end
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

    return [] if entries.empty?
    entries.map!{|e| {id: e.id, label: e.label, identifier:e.identifier, norm1: e.norm1, norm2: e.norm2}}.uniq!
    entries.map!{|e| e.merge(score: str_jaccard_sim(term, norm1, norm2, e[:label], e[:norm1], e[:norm2]))}
  end

  def self.search_term_order(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
    entries = self.search_term(dictionaries, ssdbs, threshold, term, norm1, norm2)
    entries.delete_if{|e| e[:score] < threshold}
    entries.sort_by{|e| e[:score]}.reverse
  end

  def self.search_term_top(dictionaries, ssdbs, threshold, term, norm1 = nil, norm2 = nil)
    entries = self.search_term(dictionaries, ssdbs, threshold, term, norm1, norm2)
    return [] if entries.empty?
    max_score = entries.max{|a, b| a[:score] <=> b[:score]}[:score]
    return [] if max_score < threshold
    entries = entries.delete_if{|e| e[:score] < max_score}
  end

  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  # Get typographic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize1(text, normalizer = nil)
    normalize text, 'normalization1', normalizer
  end

  def self.addition_entry_params(label, id)
    norm1 = normalize1(label)
    norm2 = normalize2(label)
    {label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, mode: Entry::MODE_ADDITION}
  end

  def self.new_for(dictionary_id, label, id, normalizer)
    norm1 = normalize1(label, normalizer)
    norm2 = normalize2(label, normalizer)
    new(label: label, identifier: id, norm1: norm1, norm2: norm2, label_length: label.length, dictionary_id: dictionary_id)
  rescue => e
    raise ArgumentError, "The entry, [#{label}, #{id}], is rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def be_normal!
    update_attribute(:mode, Entry::MODE_NORMAL)
  end

  def be_deletion!
    update_attribute(:mode, Entry::MODE_DELETION)
  end

  def addition?
    mode == Entry::MODE_ADDITION
  end

  def deletion?
    mode == Entry::MODE_DELETION
  end

  private

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

  # Compute jaccard similarity of two sets
  #
  # * (array) items1
  # * (array) items2
  #
  def self.jaccard_sim(items1, items2)
    return 0.0 if items1.empty? || items2.empty?
    (items1 & items2).size.to_f / (items1 | items2).size
  end

  # Get typographic and morphosyntactic normalization of an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def self.normalize2(text, normalizer = nil)
    normalize text, 'normalization2', normalizer
  end


  def self.normalize(text, analyzer, normalizer = nil)
    raise ArgumentError, "Empty text" if text.empty?
    _text = text.tr('{}', '()')
    body = {analyzer: analyzer, text: _text}.to_json
    res = if normalizer.nil?
            uri = URI(Rails.configuration.elasticsearch[:host])
            http = Net::HTTP.new(uri.host, uri.port)
            http.request_post('/entries/_analyze', body, {'Content-Type' => 'application/json'})
          else
            normalizer[:post].body = body
            normalizer[:http].request(normalizer[:uri], normalizer[:post])
          end
    raise res.body unless res.kind_of? Net::HTTPSuccess
    (JSON.parse res.body, symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end
end
