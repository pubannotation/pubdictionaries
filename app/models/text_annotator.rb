#!/usr/bin/env ruby
using StringScanOffset

require 'simstring'

# Provide functionalities for text annotation.
class TextAnnotator
  CHUNK_SIZE = 50_000
  BUFFER_SIZE = 1024
  MAX_CACHE_SIZE = 10_000

  OPTIONS_DEFAULT = {
    # terms will never include these words
    # no_term_words: %w(is are am be was were do did does what which when where who how an the this that these those it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g),
    no_term_words: %w(is are am be was were do did does what which when where who how an the this that these those it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought into each every many much very more most than such several some both even or but neither nor not never also much as well many e.g),

    # terms will never begin or end with these words, mostly prepositions
    no_begin_words: %w(a an about above across after against and along amid among around at before behind below beneath beside besides between beyond by concerning considering despite except excepting excluding for from in inside into like of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during),
    no_end_words: %w(about above across after against and along amid among around at before behind below beneath beside besides between beyond by concerning considering despite except excepting excluding for from in inside into like of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during),

    tokens_len_min: 1,
    tokens_len_max: 6,
    use_ngram_similarity: false,
    threshold: 0.85,
    semantic_threshold: 0.85,
    abbreviation: true,
    longest: true,
    superfluous: false,
    verbose: false
  }

  # Initialize the text annotator instance.
  #
  # * (Array) dictionaries  - The Id of dictionaries to be used for annotation.
  # * (Hash) options
#  def initialize(dictionaries, tokens_len_max = 6, threshold = 0.85, abbreviation = true, longest = false, superfluous = false, verbose=false)
  def initialize(dictionaries, options = {})
    @dictionaries = dictionaries
    @dictionaries.each do |d|
      d.additional_entries_existency_update
      d.tags_existency_update
    end
    @patterns = Pattern.active.where(dictionary_id: @dictionaries.map{|d| d.id})
    no_term_words = []
    no_begin_words = []
    no_end_words = []
    dictionaries.each do |d|
      no_term_words.concat(d.no_term_words || OPTIONS_DEFAULT[:no_term_words])
      no_begin_words.concat(d.no_begin_words || OPTIONS_DEFAULT[:no_begin_words])
      no_end_words.concat(d.no_end_words || OPTIONS_DEFAULT[:no_end_words])
    end
    @no_term_words = no_term_words.to_set
    @no_begin_words = no_begin_words.to_set
    @no_end_words = no_end_words.to_set
    @tokens_len_min = options[:tokens_len_min] || dictionaries.collect{|d| d.tokens_len_min}.min
    @tokens_len_max = options[:tokens_len_max] || dictionaries.collect{|d| d.tokens_len_max}.max
    @use_ngram_similarity = options.has_key?(:use_ngram_similarity) ? options[:use_ngram_similarity] : OPTIONS_DEFAULT[:use_ngram_similarity]
    @threshold = options[:threshold]
    @semantic_threshold = options[:semantic_threshold]
    @abbreviation = options.has_key?(:abbreviation) ? options[:abbreviation] : OPTIONS_DEFAULT[:abbreviation]
    @longest = options.has_key?(:longest) ? options[:longest] : OPTIONS_DEFAULT[:longest]
    @superfluous = options.has_key?(:superfluous) ? options[:superfluous] : OPTIONS_DEFAULT[:superfluous]
    @verbose = options.has_key?(:verbose) ? options[:verbose] : OPTIONS_DEFAULT[:verbose]

    @es_connection = Net::HTTP::Persistent.new

    # To determine the search method
    @search_method = @superfluous ? Dictionary.method(:search_term_order) : Dictionary.method(:search_term_top)

    @tokenizer_url = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @tokenizer_post = Net::HTTP::Post.new @tokenizer_url.request_uri
    @tokenizer_post['content-type'] = 'application/json'

    # to cache the results of span search
    # [] means the search result was empty
    # nil means there is no cache for the span
    @cache_span_search = {}
    @cache_access_count = 0
    @cache_access_timestamps = {}

    @soft_match = @threshold.nil? || (@threshold < 1)

    @sub_string_dbs = @dictionaries.inject({}) do |h, dic|
      sdb = if (dic.entries_num > 0) && @soft_match
        begin
          simstring_db = Simstring::Reader.new(dic.sim_string_db_path)
          simstring_db.measure = dic.simstring_method
          simstring_db.threshold = (@threshold || dic.threshold)
          simstring_db
        rescue => e
          # warn "Error during opening the Simstring DB for '#{dic.name}': #{e.message}"
          nil
        end
      else
        nil
      end
      h.merge({dic.name => sdb})
    end
  end

  def dispose
    @sub_string_dbs.each{|name, db| db.close if db}
  end

  def annotate_batch(anns_col)
    # empty the annotations
    anns_col.each do |anns|
      anns[:denotations] = []
      anns.delete(:relations)
      anns.delete(:modifications)
    end

    @cache_span_search.clear
    @cache_access_timestamps.clear
    @cache_access_count = 0

    # To remove redundant denotations
    anns_col.each do |anns|
      denotations = []
      idx_span_positions = {}
      locally_defined_abbreviations = []

      ## Beginning of pattern-based annotation
      denotations, locally_defined_abbreviations, idx_span_positions = pattern_based_annotation(anns, denotations, locally_defined_abbreviations, idx_span_positions)

      ## Beginning of dictionary-based annotation
      # find denotation candidates
      denotations, locally_defined_abbreviations, idx_span_positions = candidate_denotations(anns, denotations, locally_defined_abbreviations, idx_span_positions)

      next if denotations.empty?

      # To order denotations by their position and score
      denotations.sort! do |a, b|
        c1 = (a[:span][:begin] <=> b[:span][:begin])
        if c1.zero?
          c2 = (b[:span][:end] <=> a[:span][:end])
          c2.zero? ? (b[:score] <=> a[:score]) : c2
        else
          c1
        end
      end

      # To eliminate boundary_crossings
      to_be_removed = []
      boundary_crossings = {}
      incomplete = []
      denotations.each_with_index do |d, c|
        c_span = d[:span]

        incomplete.delete_if{|h| denotations[h][:span][:end] <= c_span[:begin]}
        boundary_crossings = incomplete.find_all{|h| denotations[h][:span][:end] < c_span[:end]}

        if boundary_crossings.empty?
          incomplete << c
        else
          max_c = boundary_crossings.max_by{|c| denotations[c][:score] }
          if d[:score] > denotations[max_c][:score]
            to_be_removed += boundary_crossings
            incomplete -= boundary_crossings
            incomplete << c
          else
            to_be_removed << c
          end
        end
      end

      to_be_removed.sort.reverse.each{|i| denotations.delete_at(i)}

      # To find embedded spans, and to remove redundant ones
      to_be_chosen = []
      embeddings = {}
      denotations.each_with_index do |d, i|
        if i == 0
          to_be_chosen << 0
        else
          c_span = d[:span]
          l_idx = to_be_chosen.last

          embeddings_for_i = if c_span[:begin] < denotations[l_idx][:span][:end] # in case of overlap (which means embedding)
            if embeddings.has_key? l_idx
              embeddings[l_idx].dup << (l_idx)
            else
              [l_idx]
            end
          elsif embeddings.has_key? l_idx # in case of non-overlap but the previous one has embeddings spans
            i_with_embedding = embeddings[l_idx].rindex{|h| denotations[h][:span][:end] >= c_span[:end]}
            if i_with_embedding
              embeddings[l_idx].first(i_with_embedding + 1)
            else
              nil
            end
          end

          if embeddings_for_i
            i_with_the_same_obj = embeddings_for_i.find{|e| denotations[e][:obj] == d[:obj]}
            if i_with_the_same_obj
              if d[:score] > denotations[i_with_the_same_obj][:score]
                to_be_chosen.delete(i_with_the_same_obj)
                embeddings_for_i.delete(i_with_the_same_obj)
                to_be_chosen << i
                embeddings[i] = embeddings_for_i if embeddings_for_i
              end
            else
              if @longest
                # to add the current one only when it ties with the last one
                if (d[:span] == denotations[l_idx][:span]) && (d[:score] == denotations[l_idx][:score])
                  to_be_chosen << i
                  embeddings[i] = embeddings_for_i
                end
              elsif @superfluous || (d[:score] >= denotations[embeddings_for_i.last][:score])
                to_be_chosen << i
                embeddings[i] = embeddings_for_i
              end
            end
          else
            to_be_chosen << i # otherwise, to add the current one
          end
        end
      end

      denotations_sel = to_be_chosen.map{|i| denotations[i]}
      denotations = denotations_sel

      # Local abbreviation annotation
      if @abbreviation
        # collection
        locally_defined_abbreviations.each do |abbr|
          denotations += idx_span_positions[abbr[:span]].collect{|p| {span:{begin:p[:begin], end:p[:end]}, string:abbr[:span], obj:abbr[:obj], score:abbr[:type]}}
        end

        denotations.uniq!{|d| [d[:span][:begin], d[:span][:end], d[:obj]]}
        denotations.sort! do |a, b|
          c = (a[:span][:begin] <=> b[:span][:begin])
          c.zero? ? (b[:span][:end] <=> a[:span][:end]) : c
        end
      end

      anns[:denotations] = denotations
    end

    anns_col
  end

  def self.time_estimation(texts)
    length = (texts.class == String) ? texts.length : texts.inject(0){|sum, text| sum += text.length}
    1 + length * 0.00001
  end

  private

  # find all the matching spans, store them in denotations, and make idx_span_positions
  # if the abbreviation option is on, make locally_defined_abbreviations
  def pattern_based_annotation(anns, denotations = [], locally_defined_abbreviations = [], idx_span_positions = {})
    return [denotations, locally_defined_abbreviations, idx_span_positions] if @patterns.empty?

    text = anns[:text]

    denotations = @patterns.map do |pattern|
      matches = text.scan_offset(/#{pattern.expression}/)
      matches.map do |m|
        mbeg, mend = m.offset(0)[0, 2]
        span = {begin:mbeg, end:mend}
        str = text[mbeg ... mend]
        {span:span, obj:pattern.identifier, score:1, string:str}
      end
    end.flatten

    [denotations, locally_defined_abbreviations, idx_span_positions]
  end

  def candidate_denotations(anns, denotations = [], locally_defined_abbreviations = [], idx_span_positions = {})
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    text = anns[:text]
    tokens = norm1_tokenize(text)
    spans  = tokens.map{|t| text[t[:start_offset] ... t[:end_offset]]}
    norm1s = tokens.map{|t| t[:token]}
    norm2s = norm2_tokenize(text).inject(Array.new(spans.length, "")){|s, t| s[t[:position]] = t[:token]; s}

    sbreaks = sentence_break(text)
    add_pars_info!(tokens, text, sbreaks)

    (0 ... tokens.length - @tokens_len_min + 1).each do |idx_token_begin|
      token_begin = tokens[idx_token_begin]

      token_span = text[token_begin[:start_offset]...token_begin[:end_offset]]

      idx_span_positions[token_span] = [] unless idx_span_positions.has_key? token_span
      idx_span_positions[token_span] << {tidx: idx_token_begin, begin:token_begin[:start_offset], end:token_begin[:end_offset]}

      next if @no_term_words.include?(token_begin[:token])
      next if @no_begin_words.include?(token_begin[:token])

      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        break if idx_token_begin + tlen > tokens.length

        idx_token_final = idx_token_begin + tlen - 1
        token_end = tokens[idx_token_final]
        break if cross_sentence?(sbreaks, token_begin[:start_offset], token_end[:end_offset])
        break if @no_term_words.include?(token_end[:token])
        # next if tlen == 1 && token_begin[:token].length == 1
        next if @no_end_words.include?(token_end[:token])

        # find the span considering the paranthesis level
        span_begin = token_begin[:start_offset]
        span_end   = token_end[:end_offset]

        case token_begin[:pars_level] - token_end[:pars_level]
        when 0
        when -1
          if token_end[:pars_close_p]
            span_end += 1
          else
            next
          end
        when 1
          if token_begin[:pars_open_p]
            span_begin -= 1
          else
            break
          end
        else
          next
        end
        span = text[span_begin...span_end]

        norm2 = norm2s[idx_token_begin, tlen].join
        next unless norm2.present?

        ## A rough checking for early break was attempted here but abandoned because it turned out the overhead was too big

        # to find terms
        entries = @cache_span_search[span]

        # Update access timestamp for LRU
        if entries
          @cache_access_timestamps[span] = @cache_access_count += 1
        end

        if entries.nil?
          norm1 = norm1s[idx_token_begin, tlen].join
          entries = @search_method.call(@dictionaries, @sub_string_dbs, @threshold, @use_ngram_similarity, nil, span, [], norm1, norm2)

          @cache_span_search[span] = entries
          @cache_access_timestamps[span] = @cache_access_count += 1

          # Implement LRU cache cleanup when size exceeds limit
          if @cache_span_search.size > MAX_CACHE_SIZE
            oldest_span = @cache_access_timestamps.min_by { |_, timestamp| timestamp }[0]
            @cache_span_search.delete(oldest_span)
            @cache_access_timestamps.delete(oldest_span)
          end
        end

        entries.each do |entry|
          # idx_token_final is added for efficiency of finding locally defined abbreviations
          d = {span:{begin:span_begin, end:span_end}, obj:entry[:identifier], score:entry[:score], string:span, idx_token_final: idx_token_final}
          if @verbose
            d[:label] = entry[:label]
            d[:norm1] = entry[:norm1]
            d[:norm2] = entry[:norm2]
          end
          denotations << d
        end
      end
    end

    # to find locally defined abbreviations
    if @abbreviation
      denotations.each do |d|
        unless d[:idx_token_final]
          d[:idx_token_final] = find_idx_token_final(d, tokens)
        end

        idx_abbr_token_first = d[:idx_token_final] + 1
        base_pars_level = tokens[idx_abbr_token_first - 1][:pars_level]

        if (idx_abbr_token_first  < tokens.length) && (tokens[idx_abbr_token_first][:pars_level] > base_pars_level)
          idx_abbr_token_final = idx_abbr_token_first

          # assumption: No case of immediately neighboring parentheses (...)(...)
          while ((idx_abbr_token_final - idx_abbr_token_first) < 3) && ((idx_abbr_token_final < tokens.length - 1) && (tokens[idx_abbr_token_final + 1][:pars_level] > base_pars_level))
            idx_abbr_token_final += 1
          end

          if (idx_abbr_token_final == tokens.length - 1) || (tokens[idx_abbr_token_final + 1][:pars_level] == base_pars_level)
            span = text[tokens[idx_abbr_token_first][:start_offset] ... tokens[idx_abbr_token_final][:end_offset]]
            # heuristic processing.
            span += ')' if text[tokens[idx_abbr_token_final][:end_offset], 2] == '))'
            abbreviation_type = determine_abbreviation(span, d[:string])
            unless abbreviation_type.nil?
              token1 = tokens[idx_abbr_token_first]
              locally_defined_abbreviations << {span:span, obj:d[:obj], type: abbreviation_type, token1: text[token1[:start_offset]...token1[:end_offset]], tlen: idx_abbr_token_final - idx_abbr_token_first + 1}
            end
          end
        end
      end

      # add additional necessary idx_span_positions
      locally_defined_abbreviations.each do |abbr|
        if abbr[:tlen] > 1
          abbr_token1s = idx_span_positions[abbr[:token1]]
          abbr_token1s.each do |token1|
            idx_abbr_token_first = token1[:tidx]
            idx_abbr_token_final = idx_abbr_token_first + abbr[:tlen] - 1
            abbr_span_begin = tokens[idx_abbr_token_first][:start_offset]
            abbr_span_begin -= 1 if abbr[:span][0] == '(' && tokens[idx_abbr_token_first][:pars_open_p]
            abbr_span_end = tokens[idx_abbr_token_final][:end_offset]
            abbr_span_end += 1 if abbr[:span][-1] == ')' && ((idx_abbr_token_final == tokens.length - 1) || (tokens[idx_abbr_token_final + 1][:pars_level] == (tokens[idx_abbr_token_first - 1][:pars_level])))
            if text[abbr_span_begin ...abbr_span_end] == abbr[:span]
              idx_span_positions[abbr[:span]] = [] unless idx_span_positions.has_key? abbr[:span]
              idx_span_positions[abbr[:span]] << {begin: abbr_span_begin, end: abbr_span_end}
            end
          end
        end
      end
    end

    denotations.each{|d| d.delete(:idx_token_final)}
    [denotations, locally_defined_abbreviations, idx_span_positions]
  end

  def find_idx_token_final(d, tokens)
    idx = tokens.bsearch_index{|x| x[:start_offset] > d[:span][:end]}
    idx - 1
  end

  def determine_abbreviation(abbr, ff)
    abbr_down = abbr.downcase

    # test a regular abbreviation form
    if ff.split(/[- ]/).collect{|w| w[0]}.join('').downcase == abbr_down
      'regAbbreviation'

    # test another regular abbreviation form
    elsif ff.scan(/[0-9A-Z]/).join('').downcase == abbr_down
      'regAbbreviation'

    # test a liberal abbreviation form
    elsif (abbr[0].downcase == ff[0].downcase) && (abbr.downcase.scan(/[0-9a-z]/) - ff.downcase.scan(/[0-9a-z]/)).empty?
      'freeAbbreviation'
    else
      nil
    end
  end

  def sentence_break(text)
    sbreaks = []
    text.scan(/[a-z0-9][.!?](?<sb>\s+)[A-Z]|(?<sb>\n)/) do |sen|
      sbreaks << Regexp.last_match.begin(:sb)
    end
    sbreaks
  end

  def cross_sentence?(sbreaks, b, e)
    !sbreaks.find{|p| p > b && p < e}.nil?
  end

  # To add parenthesis information to each token
  # (1(2)1)0((2)1)(1(2))(1(2)(2)1)
  def add_pars_info!(tokens, text, sbreaks)
    prev_token = nil
    pars_level = 0

    (0 ... tokens.length).each do |idx_token|
      if (idx_token > 0 ) && cross_sentence?(sbreaks, tokens[idx_token - 1][:end_offset], tokens[idx_token][:start_offset])
        pars_level = 0
      end

      token = tokens[idx_token]
      token_pre_span_begin = idx_token > 0 ? tokens[idx_token - 1][:end_offset] : 0
      token_pre_span = text[token_pre_span_begin ... token[:start_offset]]

      count_pars_open  = token_pre_span.count('(')
      count_pars_close = token_pre_span.count(')')

      pars_level += (count_pars_open - count_pars_close)
      pars_level = 0 if pars_level < 0

      token.merge!({pars_level:pars_level})
      token.merge!({pars_open_p:true}) if text[token[:start_offset] - 1] == '('
      token.merge!({pars_close_p:true}) if text[token[:end_offset]] == ')'
    end
  end

  def norm1_tokenize(text)
    tokenize(normalizer1, text)
  end

  def norm2_tokenize(text)
    tokenize(normalizer2, text)
  end

  def get_chunk_spans(text)
    chunk_spans = []

    t_length = text.length
    c_begin = 0
    while c_begin < t_length
      c_end = (t_length - c_begin) < CHUNK_SIZE ? t_length : c_begin + CHUNK_SIZE
      if c_end < t_length
        adjustment = text[c_end .. c_end + BUFFER_SIZE].index(/\s/)
        raise "Could not find a whitespace character" if adjustment.nil?
        c_end += adjustment
      end
      chunk_spans << [c_begin, c_end]
      c_begin = c_end
    end

    chunk_spans
  end

  def tokenize(analyzer, text)
    raise ArgumentError, "Empty text" if text.empty?

    # Get chunks in manageable sizes if the text is too long
    chunk_spans = get_chunk_spans(text)

    # Analyze each chunk and collect the results
    tokens = chunk_spans.flat_map do |span|
      @tokenizer_post.body = {analyzer: analyzer, text: text[span[0] ... span[1]].tr('{}', '()')}.to_json

      begin
        res = @es_connection.request @tokenizer_url, @tokenizer_post
      rescue => e
        raise "Bad gateway (ES). Please notify the administrator for a quick resolution."
      end

      # Parse and extract tokens from the result
      (JSON.parse(res.body, symbolize_names: true)[:tokens])
    end
  end

  def normalizer1
    @normalizer1 ||= 'normalizer1' + language_suffix
  end

  def normalizer2
    @normalizer2 ||= 'normalizer2' + language_suffix
  end

  def language_suffix
    return '' unless @dictionaries.first.language.present?

    @language_suffix ||= case @dictionaries.first.language
    when 'kor'
      '_ko'
    when 'jpn'
      '_ja'
    else
      ''
    end
  end

end