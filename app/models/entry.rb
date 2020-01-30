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

  validates :label, presence: true
  validates :identifier, presence: true

  def as_json(options={})
    {
      id: identifier,
      label: label
    }
  end

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

  def self.decapitalize(text)
    text.gsub(/(^| )[A-Z][a-z ]/, &:downcase)
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
  def self.str_jaccard_sim(str1, s1norm1, s1norm2, str2, s2norm1, s2norm2)
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

  def self.get_trigrams(str)
    return [] if str.empty?
    fstr = str[-1] + str + str[0] # to make a set of circular trigrams
    (0 .. (fstr.length - 3)).collect{|i| fstr[i .. (i + 2)]}
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
end
