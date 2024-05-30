class Entry < ApplicationRecord
  include Elasticsearch::Model

  settings index: {
    analysis: {
      filter: {
        english_stop: {
          type: :stop,
          # stop words. They will be ignored  for norm1 and norm2 indexing
          # 'an' is removed from the stopwords list for "ANS disease"
          stopwords: %w(and are as at be but by for if in into is it no not of on or such that the their then there these they this to was will with)
        }
      },
      analyzer: {
        normalizer1: { # typographic normalization
          tokenizer: :icu_tokenizer,
          filter: [:icu_folding]
        },
        normalizer2: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :icu_tokenizer,
          filter: [:icu_folding, :snowball, :english_stop]
        },
        normalizer1_ko: { # typographic normalization
          tokenizer: :nori_tokenizer,
          filter: [:icu_folding]
        },
        normalizer2_ko: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :nori_tokenizer,
          filter: [:icu_folding, :snowball, :english_stop]
        },
        normalizer1_ja: { # typographic normalization
          tokenizer: :kuromoji_tokenizer,
          filter: [:icu_folding]
        },
        normalizer2_ja: { # typographic normalization _ morphosyntactic normalization + stopword removal
          tokenizer: :kuromoji_tokenizer,
          filter: [:icu_folding, :snowball, :english_stop]
        }
      }
    }
  }

  belongs_to :dictionary
  has_many :entry_tags, dependent: :destroy
  has_many :tags, through: :entry_tags

  validates :label, presence: true
  validates :identifier, presence: true
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than: 1 }, allow_nil: true

  scope :gray, -> {where(mode: EntryMode::GRAY)}
  scope :white, -> {where(mode: EntryMode::WHITE)}
  scope :black, -> {where(mode: EntryMode::BLACK)}
  scope :custom, -> {where(mode: [EntryMode::WHITE, EntryMode::BLACK])}
  scope :active, -> {where(mode: [EntryMode::GRAY, EntryMode::WHITE])}
  scope :auto_expanded, -> {where(mode: EntryMode::AUTO_EXPANDED).order(score: :desc)}
  scope :without_black, -> {where.not(mode: EntryMode::BLACK)}

  scope :simple_paginate, -> (page = 1, per = 15) {
    offset = (page - 1) * per
    offset(offset).limit(per)
  }

  scope :narrow_by_label, -> (str, page = 0, per = nil) {
    norm1 = Dictionary.normalize1(str)
    query = where("norm1 LIKE ?", "%#{norm1}%").order(:label_length)
    per.nil? ? query.page(page) : query.page(page).per(per)
  }

  scope :narrow_by_label_prefix, -> (str, page = 0, per = nil) {
    norm1 = Dictionary.normalize1(str)
    query = where("norm1 LIKE ?", "%#{norm1}%").order(:label_length)
    per.nil? ? query.page(page) : query.page(page).per(per)
  }

  scope :narrow_by_label_prefix_and_substring, -> (str, page = 0, per = nil) {
    norm1 = Dictionary.normalize1(str)
    query = where("norm1 LIKE ? OR norm1 LIKE ?", "#{norm1}%", "_%#{norm1}%").order(:label_length)
    per.nil? ? query.page(page) : query.page(page).per(per)
  }

  scope :narrow_by_identifier, -> (str, page = 0, per = nil) {
    query = where("identifier ILIKE ?", "%#{str}%")
    per.nil? ? query.page(page) : query.page(page).per(per)
  }

  scope :narrow_by_tag, -> (tag_id, page = 0, per = nil) {
    query = joins(:tags).where(tags: { id: tag_id })
    per.nil? ? query.page(page) : query.page(page).per(per)
  }

  scope :additional_entries, -> {
    where(mode: EntryMode::WHITE, dirty: true)
  }

  def to_s
    "('#{label}', '#{identifier}')"
  end

  def as_json(options={})
    {
      id: identifier,
      label: label
    }
  end

  def to_result_hash = { label:, norm1:, norm2:, identifier:, tags: tag_values }
  def tag_values = tags.map(&:value).join('|')

  def self.as_tsv
    CSV.generate(col_sep: "\t") do |tsv|
      tsv << ['#label', :id, '#tags']
      all.each do |entry|
        tsv << [entry.label, entry.identifier, entry.tag_values]
      end
    end
  end

  def self.as_tsv_v
    CSV.generate(col_sep: "\t") do |tsv|
      tsv << ['#label', :id, '#tags', :operator]
      all.each do |entry|
        operator = case entry.mode
        when EntryMode::WHITE
          '+'
        when EntryMode::BLACK
          '-'
        end
        tsv << [entry.label, entry.identifier, entry.tag_values, operator]
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

    tags = get_tags(items[2])
    [items[0], items[1], tags]
  end

  def self.get_tags(tags)
    return [] unless tags.present?
    raise ArgumentError, 'invalid tags' unless !!(tags =~ /^([a-zA-Z0-9]+)(\|[a-zA-Z0-9]+)*$/)
    tags.split('|')
  end

  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
  end

  def be_gray!
    update_attribute(:mode, EntryMode::GRAY)
  end

  def be_white!
    update_attribute(:mode, EntryMode::WHITE)
  end

  def be_black!
    update_attribute(:mode, EntryMode::BLACK)
  end

  def is_white?
    mode == EntryMode::WHITE
  end

  def is_black?
    mode == EntryMode::BLACK
  end

  def self.normalize(text, normalizer, analyzer = nil)
    raise ArgumentError, "Empty text" unless text.present?
    _text = text.tr('{}', '()')
    body = {analyzer: normalizer, text: _text}.to_json
    res = if analyzer.nil?
            uri = URI(Rails.configuration.elasticsearch[:host])
            http = Net::HTTP.new(uri.host, uri.port)
            http.request_post('/entries/_analyze', body, {'Content-Type' => 'application/json'})
          else
            analyzer[:post].body = body
            analyzer[:http].request(analyzer[:uri], analyzer[:post])
          end
    raise res.body unless res.kind_of? Net::HTTPSuccess
    (JSON.parse res.body, symbolize_names: true)[:tokens].map{|t| t[:token]}.join('')
  end

  private

  # Compute similarity of two strings
  #
  # * (string) string1
  # * (string) string2
  #
  def self.str_sim_jaccard_3gram(str1, str2, s1norm1, s2norm1, s1norm2, s2norm2)
    str1_trigrams = get_trigrams(str1)
    str2_trigrams = get_trigrams(str2)
    s1norm1_trigrams = get_trigrams(s1norm1)
    s1norm2_trigrams = get_trigrams(s1norm2)
    s2norm1_trigrams = get_trigrams(s2norm1)
    s2norm2_trigrams = get_trigrams(s2norm2)

    if s1norm2.empty? && s2norm2.empty?
      (jaccard_sim(str1_trigrams, str2_trigrams) + jaccard_sim(s1norm1_trigrams, s2norm1_trigrams)) / 2
    else
      (jaccard_sim(str1_trigrams, str2_trigrams) + jaccard_sim(s1norm1_trigrams, s2norm1_trigrams) + 10 * jaccard_sim(s1norm2_trigrams, s2norm2_trigrams)) / 12
    end
  end

  def self.str_sim_jaccard_2gram(str1, str2, s1norm1, s2norm1, s1norm2, s2norm2)
    str1_bigrams = get_bigrams(str1)
    str2_bigrams = get_bigrams(str2)
    s1norm1_bigrams = get_bigrams(s1norm1)
    s1norm2_bigrams = get_bigrams(s1norm2)
    s2norm1_bigrams = get_bigrams(s2norm1)
    s2norm2_bigrams = get_bigrams(s2norm2)

    if s1norm2.empty? && s2norm2.empty?
      (jaccard_sim(str1_bigrams, str2_bigrams) + jaccard_sim(s1norm1_bigrams, s2norm1_bigrams)) / 2
    else
      (jaccard_sim(str1_bigrams, str2_bigrams) + jaccard_sim(s1norm1_bigrams, s2norm1_bigrams) + 10 * jaccard_sim(s1norm2_bigrams, s2norm2_bigrams)) / 12
    end
  end

  def self.str_sim_jp(str1, str2, s1norm1 = nil, s2norm1 = nil, s1norm2 = nil, s2norm2 = nil)
    sim1 = String::Similarity.cosine(str1, str2, ngram:1)
    sim2 = String::Similarity.cosine(str1, str2, ngram:2)
    (sim1 * 0.7) + (sim2 * 0.3)
  end

  def self.get_unigrams(str)
    return [] if str.empty?
    str.split(//)
  end

  def self.get_bigrams(str)
    return [] if str.empty?
    fstr = str + str[0] # to make a set of circular bigrams
    (0 .. (fstr.length - 2)).collect{|i| fstr[i, 2]}
  end

  def self.get_trigrams(str)
    return [] if str.nil? || str.empty?
    fstr = str[-1] + str + str[0] # to make a set of circular trigrams
    (0 .. (fstr.length - 3)).collect{|i| fstr[i, 3]}
  end

  # Compute the jaccard similarity of two sets
  #
  # * (array) items1
  # * (array) items2
  #
  def self.jaccard_sim(items1, items2)
    return 0.0 if items1.empty? || items2.empty?
    (items1 & items2).size.to_f / (items1 | items2).size
  end
end
