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
    # index spans with their positions and norms
    span_index = anns_col.each_with_index.inject({}){|index, (anns, i)| index_spans(anns[:text], i, index)}

    # To search mapping entries per span
    span_entries = {}
    span_index.each do |span, info|
      entries = Entry.search_term(@dictionaries, @sub_string_dbs, @threshold, span, info[:norm1], info[:norm2])
      span_entries[span] = entries if entries.present?
    end

    # To collect annotated (anchored) spans per entry
    entry_anns = Hash.new([])
    span_entries.each do |span, entries|
      entries.each do |entry|
        entry_anns[entry[:identifier]] += span_index[span][:positions].collect{|p| {span:span, position:p, label:entry[:label], norm2:entry[:norm2], identifier:entry[:identifier], score:entry[:score]}}
      end
    end

    # To sort anns by their position
    entry_anns.each_value do |anns|
      anns.sort! do |a, b|
        c = (a[:position][:text_idx] <=> b[:position][:text_idx])
        c = c.zero? ? (a[:position][:start_offset] <=> b[:position][:start_offset]) : c
        c.zero? ? (b[:position][:end_offset] <=> a[:position][:end_offset]) : c
      end
    end

    # To choose the best annotated span per entry
    entry_anns.each do |eid, anns|
      full_anns = anns
      best_anns = []

      full_anns.each do |ann|
        if best_anns.empty?
          best_anns.push(ann)
        else
          last_ann = best_anns.pop
          if (ann[:position][:text_idx] == last_ann[:position][:text_idx]) && (ann[:position][:start_offset] < last_ann[:position][:end_offset]) #span_overlap?
            best_anns.push(ann[:score] > last_ann[:score] ? ann : last_ann) # to prefer shorter span
          else
            best_anns.push(last_ann, ann)
          end
        end
      end
      entry_anns[eid] = best_anns
    end

    # rewrite to denotations
    anns_col.each do |anns|
      anns[:denotations] = []
      anns.delete(:relations)
      anns.delete(:modifications)
    end

    entry_anns.each do |eid, anns|
      anns.each do |ann|
        d = {span:{begin:ann[:position][:start_offset], end:ann[:position][:end_offset]}, obj:ann[:identifier]}
        if @rich
          d[:score] = ann[:score]
          d[:label] = ann[:label]
          d[:norm2] = ann[:norm2]
        end
        anns_col[ann[:position][:text_idx]][:denotations] << d
      end
    end

    anns_col.each{|anns| anns[:denotations].uniq!}
    anns_col
  end

  def annotate(text, denotations = [])
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    tokens = norm1_tokenize(Entry.decapitalize(text))
    spans  = tokens.map{|t| text[t[:start_offset] ... t[:end_offset]]}

    norm1s = spans.map{|s| Entry.normalize1(s)}
    norm2s = spans.map{|s| norm2_tokenize(s)}

    # index spans with their tokens and positions (array)
    span_index = {}
    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      next if NO_TERM_WORDS.include?(tokens[tbegin][:token])
      next if NO_EDGE_WORDS.include?(tokens[tbegin][:token])

      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        break if tbegin + tlen > tokens.length
        break if (tokens[tbegin + tlen - 1][:position] - tokens[tbegin][:position]) + 1 > @tokens_len_max
        # break if tlen > 1 && text[tokens[tbegin + tlen - 2][:start_offset] ... tokens[tbegin + tlen - 1][:end_offset]] =~ /[^A-Z]\.\s+[A-Z][a-z ]/ # sentence boundary
        break if NO_TERM_WORDS.include?(tokens[tbegin + tlen - 1][:token])
        next if NO_EDGE_WORDS.include?(tokens[tbegin + tlen - 1][:token])

        norm2 = norm2s[tbegin, tlen].join
        lookup = @dictionaries.inject([]){|col, dic| col += @sub_string_dbs_overlap[dic.name].retrieve(norm2)}
        break if lookup.empty?

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]

        unless span_index.has_key?(span)
          norm1 = norm1s[tbegin, tlen].join
          span_index[span] = {norm1:norm1, norm2:norm2, positions:[]}
        end

        position = {start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}
        span_index[span][:positions] << position
      end
    end

    # To search mapping entries per span
    span_entries = {}

    bad_key = nil
    span_index.each do |span, info|
      entries = Entry.search_term(@dictionaries, @sub_string_dbs, @threshold, span, info[:norm1], info[:norm2])

      if entries.present?
        span_entries[span] = entries
      end
    end

    # To collect annotated (anchored) spans per entry
    entry_anns = Hash.new([])
    span_entries.each do |span, entries|
      entries.each do |entry|
        entry_anns[entry[:id]] += span_index[span][:positions].collect{|p| {span:span, position:p, label:entry[:label], identifier:entry[:identifier], score:entry[:score]}}
      end
    end

    # To sort the spans. unnecessary at the moment, because already sorted.
    # sort{|a, b|
    #   span_index[a][:start_offset] == span_index[b][:start_offset] ?
    #   span_index[b][:end_offset] <=> span_index[a][:end_offset] :
    #   span_index[a][:start_offset] <=> span_index[b][:start_offset]
    # }

    # To choose the best annotated span per entry
    entry_anns.each do |eid, anns|
      full_anns = anns
      best_anns = []
      full_anns.each do |ann|
        last_ann = best_anns.pop
        if last_ann.nil?
          best_anns.push(ann)
        elsif ann[:position][:start_offset] < last_ann[:position][:end_offset] #span_overlap?
          best_anns.push(ann[:score] > last_ann[:score] ? ann : last_ann) # prefer shorter span
        else
          best_anns.push(last_ann, ann)
        end
      end
      entry_anns[eid] = best_anns
    end

    # rewrite to denotations
    denotations = []
    entry_anns.each do |eid, anns|
      anns.each do |ann|
        d = {span:{begin:ann[:position][:start_offset], end:ann[:position][:end_offset]}, obj:ann[:identifier]}
        if @rich
          d[:score] = ann[:score]
          d[:label] = ann[:label]
        end
        denotations << d
      end
    end

    {
      text: text,
      denotations: denotations.uniq
    }
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