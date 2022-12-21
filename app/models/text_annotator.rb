#!/usr/bin/env ruby
using StringScanOffset

require 'simstring'

# Provide functionalities for text annotation.
class TextAnnotator
  OPTIONS_DEFAULT = {
    # terms will never include these words
    # no_term_words: %w(is are am be was were do did does what which when where who how an the this that these those it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought each every many much very more most than such several some both even and or but neither nor not never also much as well many e.g),
    no_term_words: %w(is are am be was were do did does what which when where who how an the this that these those it its we our us they their them there then I he she my me his him her will shall may can cannot would should might could ought into each every many much very more most than such several some both even or but neither nor not never also much as well many e.g),

    # terms will never begin or end with these words, mostly prepositions
    no_begin_words: %w(a an about above across after against and along amid among around at before behind below beneath beside besides between beyond by concerning considering despite except excepting excluding for from in inside into like of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during),
    no_end_words: %w(about above across after against and along amid among around at before behind below beneath beside besides between beyond by concerning considering despite except excepting excluding for from in inside into like of off on onto regarding since through to toward towards under underneath unlike until upon versus via with within without during),

    tokens_len_min: 1,
    tokens_len_max: 6,
    threshold: 0.85,
    abbreviation: false,
    longest: false,
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
    @patterns = Pattern.active.where(dictionary_id: @dictionaries.map{|d| d.id})
    @no_term_words = dictionaries.collect{|d| d.no_term_words || OPTIONS_DEFAULT[:no_term_words]}.reduce(:+).uniq
    @no_begin_words = dictionaries.collect{|d| d.no_begin_words || OPTIONS_DEFAULT[:no_begin_words]}.reduce(:+).uniq
    @no_end_words = dictionaries.collect{|d| d.no_end_words || OPTIONS_DEFAULT[:no_end_words]}.reduce(:+).uniq
    @tokens_len_min = options[:tokens_len_min] || dictionaries.collect{|d| d.tokens_len_min}.min
    @tokens_len_max = options[:tokens_len_max] || dictionaries.collect{|d| d.tokens_len_max}.max
    @threshold = options[:threshold]
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

    @sub_string_dbs = @dictionaries.inject({}) do |h, dic|
      sdb = if dic.entries_num > 0
        begin
          simstring_db = Simstring::Reader.new(dic.sim_string_db_path)
          simstring_db.measure = dic.simstring_method
          simstring_db.threshold = (@threshold || dic.threshold)
          simstring_db
        rescue => e
          raise "Error during opening the Simstring DB for '#{dic.name}': #{e.message}"
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

    # To remove redundant denotations
    anns_col.each do |anns|
      denotations = []
      idx_span_positions = {}
      idx_position_abbreviation_candidates = {}

      ## Beginning of pattern-based annotation
      denotations, idx_position_abbreviation_candidates, idx_span_positions = pattern_based_annotation(anns, denotations, idx_position_abbreviation_candidates, idx_span_positions)

      ## Beginning of dictionary-based annotation
      # find denotation candidates
      denotations, idx_position_abbreviation_candidates, idx_span_positions = candidate_denotations(anns, denotations, idx_position_abbreviation_candidates, idx_span_positions)

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
        denotations.each do |d|
          if idx_position_abbreviation_candidates.has_key?(d[:span][:end])
            abbr = idx_position_abbreviation_candidates[d[:span][:end]]
            denotations += idx_span_positions[abbr[:span]].collect{|p| {span:p, obj:abbr[:obj], score:abbr[:type]}}
          end
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

  def pattern_based_annotation(anns, denotations = [], idx_position_abbreviation_candidates = {}, idx_span_positions = {})
    return [denotations, idx_position_abbreviation_candidates, idx_span_positions] if @patterns.empty?

    text = anns[:text]

    denotations = @patterns.map do |pattern|
      matches = text.scan_offset(/#{pattern.expression}/)
      matches.map do |m|
        mbeg, mend = m.offset(0)[0, 2]
        span = {begin:mbeg, end:mend}

        str = text[mbeg ... mend]
        idx_span_positions[str] = [] unless idx_span_positions.has_key? str
        idx_span_positions[str] << span

        # to find abbreviation definitions
        if @abbreviation
          pos = mend
          pos += 1 while text[pos] =~ /\s/
          if text[pos] == '('
            pos += 1
            abeg = pos
            pos += 1 while text[pos] != ')' && pos - abeg < 10
            aend = pos if text[pos] == ')'
          end

          if aend.present? && aend > abeg + 1
            abbr_str = text[abeg ... aend]
            abbreviation_type = determine_abbreviation(abbr_str, str)
            idx_position_abbreviation_candidates[mend] = {span:abbr_str, obj:pattern.identifier, type: abbreviation_type} unless abbreviation_type.nil?
          end
        end

        {span:span, obj:pattern.identifier, score:1, string:str}
      end
    end.reduce(:union)

    [denotations, idx_position_abbreviation_candidates, idx_span_positions]
  end

  def candidate_denotations(anns, denotations = [], idx_position_abbreviation_candidates = {}, idx_span_positions = {})
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
      idx_span_positions[token_span] << {begin:token_begin[:start_offset], end:token_begin[:end_offset]}

      next if @no_term_words.include?(token_begin[:token])
      next if @no_begin_words.include?(token_begin[:token])

      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        break if idx_token_begin + tlen > tokens.length

        idx_token_end = idx_token_begin + tlen - 1
        token_end = tokens[idx_token_end]
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

        if entries.nil?
          norm1 = norm1s[idx_token_begin, tlen].join
          entries = @search_method.call(@dictionaries, @sub_string_dbs, @threshold, span, norm1, norm2)

          if entries.present?
            # cache all the positive search results
            @cache_span_search[span] = entries
          else
            # cache negative search results up to bigrams
            @cache_span_search[span] = entries if tlen <= 2
          end
        end

        entries.each do |entry|
          d = {span:{begin:span_begin, end:span_end}, obj:entry[:identifier], score:entry[:score], string:span}
          if @verbose
            d[:label] = entry[:label]
            d[:norm1] = entry[:norm1]
            d[:norm2] = entry[:norm2]
          end
          denotations << d
        end

        # to find abbreviation definitions
        if @abbreviation
          if idx_token_begin > 0 && tlen == 1 && span.length > 1 && token_begin[:pars_open_p] && token_end[:pars_close_p]
            di = denotations.length - 1
            while di >= 0 && denotations[di][:span][:end] >= tokens[idx_token_begin - 1][:end_offset]
              if denotations[di][:span][:end] == tokens[idx_token_begin - 1][:end_offset]
                ff_denotation = denotations[di]
                abbreviation_type = determine_abbreviation(span, ff_denotation[:string])
                idx_position_abbreviation_candidates[ff_denotation[:span][:end]] = {span:span, obj:ff_denotation[:obj], type: abbreviation_type} unless abbreviation_type.nil?
              end
              di -= 1
            end
          end
        end
      end
    end

    [denotations, idx_position_abbreviation_candidates, idx_span_positions]
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
    elsif (abbr[0].downcase == ff[0].downcase) && (abbr.downcase.chars - ff.downcase.chars).empty?
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
  def add_pars_info!(tokens, text, sbreaks)
    prev_token = nil
    pars_level = 0
    tokens.each do |token|
      if prev_token && cross_sentence?(sbreaks, prev_token[:end_offset], token[:start_offset])
        prev_token = nil
        pars_level = 0
      end

      start_offset = token[:start_offset]
      pars_open_p  = start_offset > 0 && text[start_offset - 1] == '('
      pars_close_p = text[token[:end_offset]] == ')'

      if prev_token
        count_pars_open  = text[prev_token[:end_offset] ... start_offset].count('(')
        count_pars_close = text[prev_token[:end_offset] ... start_offset].count(')')
        pars_level += (count_pars_open - count_pars_close)
        pars_level = 0 if pars_level < 0
      end

      token.merge!({pars_open_p:pars_open_p, pars_close_p:pars_close_p, pars_level:pars_level})
      prev_token = token
    end
  end

  def norm1_tokenize(text)
    tokenize(normalizer1, text)
  end

  def norm2_tokenize(text)
    tokenize(normalizer2, text)
  end

  def tokenize(analyzer, text)
    raise ArgumentError, "Empty text" if text.empty?
    @tokenizer_post.body = {analyzer: analyzer, text: text.tr('{}', '()')}.to_json
    res = @es_connection.request @tokenizer_url, @tokenizer_post
    (JSON.parse res.body, symbolize_names: true)[:tokens]
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