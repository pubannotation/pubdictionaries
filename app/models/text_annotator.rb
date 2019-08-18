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
  def initialize(dictionaries, tokens_len_max = 6, threshold = 0.85, abbreviation = true, longest = false, superfluous = false, verbose=false)
    @dictionaries = dictionaries
    @tokens_len_max = tokens_len_max
    @threshold = threshold
    @abbreviation = abbreviation
    @longest = longest
    @superfluous = superfluous
    @verbose = verbose

    @tokens_len_min ||= 1
    @tokens_len_max ||= 6
    @threshold ||= 0.85

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

    # To determine the search method
    search_method = @superfluous ? Entry.method(:search_term_order) : Entry.method(:search_term_top)

    # To perform the search
    span_index.each do |span, info|
      entries = search_method.call(@dictionaries, @sub_string_dbs, @threshold, span, info[:norm1], info[:norm2])
      span_entries[span] = entries if entries.present?
    end

    # rewite to denotations
    span_entries.each do |span, entries|
      locs = span_index[span][:positions]
      locs.each do |loc|
        entries.each do |entry|
          d = {span:{begin:loc[:start_offset], end:loc[:end_offset]}, obj:entry[:identifier], score:entry[:score]}
          if @verbose
            d[:label] = entry[:label]
            d[:norm1] = entry[:norm1]
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
        c1 = (a[:span][:begin] <=> b[:span][:begin])
        if c1.zero?
          c2 = (b[:span][:end] <=> a[:span][:end])
          c2.zero? ? (b[:score] <=> a[:score]) : c2
        else
          c1
        end
      end

      denotations_sel = []
      denotations.each do |d|
        if denotations_sel.empty?
          denotations_sel << d
        else
          last_denotation = denotations_sel.last
          if ((d[:obj] == last_denotation[:obj]) && (d[:span][:begin] < last_denotation[:span][:end])) # span_overlap with the same obj
            denotations_sel[-1] = d if d[:score] > last_denotation[:score] # to choose the one with higher score, preferring the shorter span
          elsif (d[:span][:end] <= last_denotation[:span][:end]) # embedded span
            if @longest
              denotations_sel << d if ((d[:span] == last_denotation[:span]) && (d[:score] == last_denotation[:score]))
              # do not choose
            elsif @superfluous || (d[:score] >= last_denotation[:score])
              denotations_sel << d # to choose it
            else
              # do not choose
            end
          else
            denotations_sel << d # to choose all others
          end
        end
      end
      anns[:denotations] = denotations_sel
    end

    ## Local abbreviation annotation
    if @abbreviation
      anns_col.each_with_index do |anns, i|
        denotations = anns[:denotations]
        text = anns[:text]

        # collection
        abbrs = []
        denotations.each do |d|
          if abbrs.last && d[:span][:end] == abbrs.last[:ff_span][:end] && abbrs.last[:score] == 'regAbbreviation'
            if d[:span][:begin] == abbrs.last[:ff_span][:begin]
              abbrs << {ff_span: d[:span], span:abbrs.last[:span], abbr: abbrs.last[:abbr], obj: d[:obj], score: 'regAbbreviation'}
            else
              next
            end
          end

          abbr_begin, abbr_end = if abbrs.last && d[:span][:end] == abbrs.last[:ff_span][:end]
            abbrs.last[:span]
          else
            _abbr_begin = d[:span][:end] + 1
            _abbr_begin += 1 while text[_abbr_begin] == ' '
            next unless text[_abbr_begin] == '('
            _abbr_begin += 1

            _abbr_end = text.index(')', _abbr_begin + 1)
            [_abbr_begin, _abbr_end]
          end

          next if abbr_end.nil?
          next if (abbr_end - abbr_begin) >= (d[:span][:end] - d[:span][:begin]) # an abbreviation may not be longer than the full form.

          abbr = text[abbr_begin ... abbr_end]
          next if abbr.index(' ') # an abbreviation may not include a space

          term = text[d[:span][:begin] ... d[:span][:end]]
          abbr_down = abbr.downcase

          # test a regular abbreviation form
          if term.split.collect{|w| w[0]}.join('').downcase == abbr_down
            abbrs << {ff_span: d[:span], span:[begin:abbr_begin, end:abbr_end], abbr: abbr, obj: d[:obj], score: 'regAbbreviation'}

          # test another regular abbreviation form
          elsif term.scan(/[0-9A-Z]/).join('').downcase == abbr_down
            abbrs << {ff_span: d[:span], span:[begin:abbr_begin, end:abbr_end], abbr: abbr, obj: d[:obj], score: 'regAbbreviation'}

          # test a liberal abbreviation form
          elsif (abbrs.last) && (abbr.downcase.chars - term.chars).empty?
            if abbrs.last && (d[:span][:end] == abbrs.last[:ff_span][:end])
              abbrs.last = {ff_span: d[:span], span:[begin:abbr_begin, end:abbr_end], abbr: abbr, obj: d[:obj], score: 'freeAbbreviation'}
            else
              abbrs << {ff_span: d[:span], span:[begin:abbr_begin, end:abbr_end], abbr: abbr, obj: d[:obj], score: 'freeAbbreviation'}
            end
          end
        end

        # annotation
        unless abbrs.empty?
          abbrs.each do |abbr|
            locs = span_index[abbr[:abbr]][:positions].select{|p| p[:text_idx] == i}
            locs.each do |loc|
              denotations <<  {span:{begin:loc[:start_offset], end:loc[:end_offset]}, obj:abbr[:obj], score:abbr[:score]}
            end
          end

          denotations.uniq!{|d| [d[:span][:begin], d[:span][:end], d[:obj]]}
          denotations.sort! do |a, b|
            c = (a[:span][:begin] <=> b[:span][:begin])
            c.zero? ? (b[:span][:end] <=> a[:span][:end]) : c
          end
        end
      end
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