#!/usr/bin/env ruby
require 'simstring'

# Provide functionalities for text annotation.
class TextAnnotator
  # terms will never include these words
  NO_TERM_WORDS = %w(is are am be was were do did does what which when where who how an the this that these those it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g)

  # terms will never begin or end with these words, mostly prepositions
  NO_EDGE_WORDS = %w(about above across after against along amid among around at before behind below beneath beside besides between beyond by concerning considering despite except excepting excluding for from in inside into like of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during)

  # Initialize the text annotator instance.
  #
  # * (array)  dictionaries  - The Id of dictionaries to be used for annotation.
  def initialize(dictionaries, tokens_len_max = 6, threshold = 0.85, rich=false)
    @dictionaries = dictionaries
    @tokens_len_max = tokens_len_max
    @threshold = threshold
    @rich = rich

    @tokens_len_min ||= 1
    @tokens_len_max ||= 6
    @threshold ||= 0.85
    @rich ||= false

    @es_connection = Net::HTTP::Persistent.new

    @tokenizer_url = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @tokenizer_post = Net::HTTP::Post.new @tokenizer_url.request_uri
    @tokenizer_post['content-type'] = 'application/json'

    @sub_string_dbs = @dictionaries.inject({}) do |h, dic|
      h[dic.name] = begin
        Simstring::Reader.new(dic.sim_string_db_path)
      rescue
        nil
      end
      if h[dic.name]
        h[dic.name].measure = Simstring::Jaccard
        h[dic.name].threshold = @threshold * 0.7
      end
      h
    end

    @sub_string_dbs_overlap = @dictionaries.inject({}) do |h, dic|
      h[dic.name] = begin
        Simstring::Reader.new(dic.sim_string_db_path)
      rescue
        nil
      end
      if h[dic.name]
        h[dic.name].measure = Simstring::Overlap
        h[dic.name].threshold = @threshold * 0.7
      end
      h
    end

    @tmp_sub_string_dbs_overlap = @dictionaries.inject({}) do |h, dic|
      h[dic.name] = begin
        Simstring::Reader.new(dic.tmp_sim_string_db_path)
      rescue
        nil
      end
      if h[dic.name]
        h[dic.name].measure = Simstring::Overlap
        h[dic.name].threshold = @threshold * 0.7
      end
      h
    end
  end

  def dispose
    @sub_string_dbs.each{|name, db| db.close if db}
    @sub_string_dbs_overlap.each{|name, db| db.close if db}
    @tmp_sub_string_dbs_overlap.each{|name, db| db.close if db}
  end

  def annotate_batch(anns_col)
    # empty the annotations
    anns_col.each do |anns|
      anns[:denotations] = []
      anns.delete(:relations)
      anns.delete(:modifications)
    end

    # index spans with their positions and norms
    span_index = anns_col.each_with_index.inject({}){|index, (anns, i)| index_spans(anns[:text], i, index)}

    # To search mapping entries per span
    span_entries = {}
    span_index.each do |span, info|
      entries = Entry.search_term_top(@dictionaries, @sub_string_dbs, @threshold, span, info[:norm1], info[:norm2])
      span_entries[span] = entries if entries.present?
    end

    # rewite to denotations
    span_entries.each do |span, entries|
      locs = span_index[span][:positions]
      locs.each do |loc|
        entries.each do |entry|
          d = {span:{begin:loc[:start_offset], end:loc[:end_offset]}, obj:entry[:identifier], score:entry[:score]}
          if @rich
            d[:label] = entry[:label]
            d[:norm2] = entry[:norm2]
          end
          anns_col[loc[:text_idx]][:denotations] << d
        end
      end
    end

    anns_col.each{|anns| anns[:denotations].uniq!}

    # To remove unnecessary denotations
    anns_col.each do |anns|
      denotations = anns[:denotations]
      next unless denotations.length > 1

      # To sort denotations by their position
      denotations.sort! do |a, b|
        c = (a[:span][:begin] <=> b[:span][:begin])
        c.zero? ? (b[:span][:end] <=> a[:span][:end]) : c
      end

      denotations_sel = []
      denotations.each do |d|
        if denotations_sel.empty?
          denotations_sel << d
        else
          last_denotation = denotations_sel.last
          if ((d[:obj] == last_denotation[:obj]) && (d[:span][:begin] < last_denotation[:span][:end])) # span_overlap with the same obj
            denotations_sel[-1] = d if d[:score] > last_denotation[:score] # to choose the one with higher score, preferring the shorter span
          elsif ((d[:span][:end] < last_denotation[:span][:end]) && (d[:score] < last_denotation[:score])) # embedded span with lower score than the embedding one
            # do not choose
          else
            denotations_sel << d # to choose all others
          end
        end
      end
      anns[:denotations] = denotations_sel
    end

    anns_col
  end

  def self.time_estimation(texts)
    length = (texts.class == String) ? texts.length : texts.inject(0){|sum, text| sum += text.length}
    1 + length * 0.00001
  end

  private

  def index_spans(text, text_idx, span_index)
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    tokens = norm1_tokenize(text)
    spans  = tokens.map{|t| text[t[:start_offset] ... t[:end_offset]]}
    norm1s = tokens.map{|t| t[:token]}
    norm2s = norm2_tokenize(text).inject(Array.new(spans.length, "")){|s, t| s[t[:position]] = t[:token]; s}

    sbreaks = sentence_break(text)

    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      next if NO_TERM_WORDS.include?(tokens[tbegin][:token])
      next if NO_EDGE_WORDS.include?(tokens[tbegin][:token])

      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        break if tbegin + tlen > tokens.length
        break if (tokens[tbegin + tlen - 1][:position] - tokens[tbegin][:position]) + 1 > @tokens_len_max
        break if cross_sentence(sbreaks, tokens[tbegin][:start_offset], tokens[tbegin + tlen - 1][:end_offset])
        break if NO_TERM_WORDS.include?(tokens[tbegin + tlen - 1][:token])
        next if NO_EDGE_WORDS.include?(tokens[tbegin + tlen - 1][:token])

        norm2 = norm2s[tbegin, tlen].join

        if tlen > 2 # It seems SimString require the string to be longer than 2 for Overlap matching
          lookup = @dictionaries.inject([]) do |col, dic|
            col += @sub_string_dbs_overlap[dic.name].retrieve(norm2) unless @sub_string_dbs_overlap[dic.name].nil?
            col += @tmp_sub_string_dbs_overlap[dic.name].retrieve(norm2) unless @tmp_sub_string_dbs_overlap[dic.name].nil?
            col
          end
          break if lookup.empty?
        end

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]

        unless span_index.has_key?(span)
          norm1 = norm1s[tbegin, tlen].join
          span_index[span] = {norm1:norm1, norm2:norm2, positions:[]}
        end

        position = {text_idx: text_idx, start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}
        span_index[span][:positions] << position
      end
    end

    span_index
  end

  def sentence_break(text)
    sbreaks = []
    text.scan(/[a-z0-9][.!?](?<sb>\s+)[A-Z]/) do |sen|
      sbreaks << Regexp.last_match.begin(:sb)
    end
    sbreaks
  end

  def cross_sentence(sbreaks, b, e)
    !sbreaks.find{|p| p > b && p < e}.nil?
  end

  def norm1_tokenize(text)
    tokenize('normalization1', text)
  end

  def norm2_tokenize(text)
    tokenize('normalization2', text)
  end

  def tokenize(analyzer, text)
    raise ArgumentError, "Empty text" if text.empty?
    @tokenizer_post.body = {analyzer: analyzer, text: text.tr('{}', '()')}.to_json
    res = @es_connection.request @tokenizer_url, @tokenizer_post
    (JSON.parse res.body, symbolize_names: true)[:tokens]
  end
end