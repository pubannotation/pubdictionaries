#!/usr/bin/env ruby
using StringScanOffset

require 'simstring'

# Provide functionalities for text annotation.
class TextAnnotator
  CHUNK_SIZE = 50_000
  BUFFER_SIZE = 1024

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
    semantic_threshold: 0.7,
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

    @soft_match = @threshold.nil? || (@threshold < 1)

    # Create semantic temp tables for dictionaries with embeddings (for fast HNSW-based search)
    # Only create temp tables if semantic search is enabled
    @semantic_temp_tables = {}
    if @semantic_threshold.present? && @semantic_threshold > 0
      @dictionaries.each do |dic|
        # Only create temp table for dictionaries with embeddings populated
        if dic.entries_num > 0 && dic.embeddings_populated?
          begin
            table_name = dic.create_semantic_temp_table!
            @semantic_temp_tables[dic.id] = table_name
            Rails.logger.info "Created semantic temp table for dictionary #{dic.name}"
          rescue => e
            Rails.logger.warn "Failed to create semantic temp table for #{dic.name}: #{e.message}"
            # Fall back to regular batch_search_semantic
          end
        end
      end
    end

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

    # Clean up semantic temp tables
    @semantic_temp_tables.each do |dict_id, table_name|
      begin
        ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{table_name}")
        Rails.logger.debug "Dropped semantic temp table #{table_name}"
      rescue => e
        Rails.logger.warn "Failed to drop temp table #{table_name}: #{e.message}"
      end
    end
  end

  def annotate_batch(anns_col)
    # empty the annotations
    anns_col.each do |anns|
      anns[:denotations] = []
      anns.delete(:relations)
      anns.delete(:modifications)
    end

    # To remove redundant denotations
    anns_col.each do |anns|
      denotations = []
      idx_span_positions = {}
      locally_defined_abbreviations = []

      # Filter dictionaries by context similarity
      filtered_dictionaries = @semantic_threshold.present? ? filter_dictionaries_by_context(anns[:text]) : @dictionaries
      next if filtered_dictionaries.empty?

      ## Beginning of pattern-based annotation
      denotations, locally_defined_abbreviations, idx_span_positions = pattern_based_annotation(anns, denotations, locally_defined_abbreviations, idx_span_positions, filtered_dictionaries)

      ## Beginning of dictionary-based annotation
      # find denotation candidates
      denotations, locally_defined_abbreviations, idx_span_positions = candidate_denotations(anns, denotations, locally_defined_abbreviations, idx_span_positions, filtered_dictionaries)

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

  def context_similarities
    Rails.logger.debug "context_similarities called, returning: #{(@context_similarities || {}).inspect}"
    @context_similarities || {}
  end

  private

  def filter_dictionaries_by_context(text)
    Rails.logger.debug "filter_dictionaries_by_context called with text length: #{text.length}"
    text_embedding = EmbeddingServer.fetch_embedding(text)

    # Always calculate similarities for display, even if no threshold is set
    if text_embedding.blank?
      Rails.logger.debug "No text embedding available"
      @context_similarities = {}
      return @dictionaries
    end

    text_embedding_vector = "[#{text_embedding.map(&:to_f).join(',')}]"

    # Initialize similarity scores storage
    @context_similarities = {}
    Rails.logger.debug "Initialized context_similarities: #{@context_similarities}"

    filtered = @dictionaries.select do |dictionary|
      if dictionary.context_embedding.blank?
        @context_similarities[dictionary.name] = nil
        next true
      end

      # Calculate cosine similarity (1 - cosine distance)
      begin
        result = ActiveRecord::Base.connection.exec_query(
          "SELECT $1::vector <=> $2::vector AS distance",
          "context_similarity",
          [text_embedding_vector, dictionary.context_embedding.to_s]
        )
        similarity = 1.0 - result.first['distance'].to_f
        @context_similarities[dictionary.name] = similarity
        # Only filter if semantic_threshold is set
        @semantic_threshold.nil? || similarity >= @semantic_threshold
      rescue => e
        # If there's an error with vector comparison, include the dictionary
        Rails.logger.warn "Error comparing context embeddings: #{e.message}"
        @context_similarities[dictionary.name] = nil
        true
      end
    end

    filtered
  end

  # find all the matching spans, store them in denotations, and make idx_span_positions
  # if the abbreviation option is on, make locally_defined_abbreviations
  def pattern_based_annotation(anns, denotations = [], locally_defined_abbreviations = [], idx_span_positions = {}, dictionaries = @dictionaries)
    filtered_patterns = @patterns.select { |p| dictionaries.any? { |d| d.id == p.dictionary_id } }
    return [denotations, locally_defined_abbreviations, idx_span_positions] if filtered_patterns.empty?

    text = anns[:text]

    denotations = filtered_patterns.map do |pattern|
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

  def candidate_denotations(anns, denotations = [], locally_defined_abbreviations = [], idx_span_positions = {}, dictionaries = @dictionaries)
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    text = anns[:text]
    tokens = norm1_tokenize(text)
    spans  = tokens.map{|t| text[t[:start_offset] ... t[:end_offset]]}
    norm1s = tokens.map{|t| t[:token]}
    norm2s = norm2_tokenize(text).inject(Array.new(spans.length, "")){|s, t| s[t[:position]] = t[:token]; s}

    sbreaks = sentence_break(text)
    add_pars_info!(tokens, text, sbreaks)

    # Step 1: Pre-generate all valid spans with their boundary information
    span_index = pre_generate_spans(text, tokens, norm1s, norm2s, sbreaks, idx_span_positions)

    # Step 2: Batch get embeddings for all spans
    if @semantic_threshold.present? && @semantic_threshold > 0
      batch_get_embeddings(span_index)
    end

    # Step 3: Batch get identifiers for all spans from dictionaries
    batch_get_identifiers(span_index, dictionaries)

    # Step 4: Generate denotations from spans with found identifiers (single pass)
    generate_denotations_from_spans(span_index, denotations)

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

  # Pre-generate all valid spans with their boundary information
  # Returns a hash where keys are span strings and values contain:
  #   - span_begin, span_end: character offsets
  #   - idx_token_begin, idx_token_final: token indices
  #   - norm1, norm2: normalized forms
  #   - entries: (to be filled by batch_get_identifiers)
  #   - embedding: (to be filled by batch_get_embeddings)
  def pre_generate_spans(text, tokens, norm1s, norm2s, sbreaks, idx_span_positions)
    span_index = {}

    (0 ... tokens.length - @tokens_len_min + 1).each do |idx_token_begin|
      token_begin = tokens[idx_token_begin]

      # Track single token positions
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
        next if @no_end_words.include?(token_end[:token])

        # find the span considering the parenthesis level
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
        norm1 = norm1s[idx_token_begin, tlen].join
        norm2 = norm2s[idx_token_begin, tlen].join
        next unless norm2.present?

        # Store span with all its boundary information
        span_index[span] = {
          span_begin: span_begin,
          span_end: span_end,
          idx_token_begin: idx_token_begin,
          idx_token_final: idx_token_final,
          norm1: norm1,
          norm2: norm2,
          entries: []  # to be filled by batch_get_identifiers
        }
      end
    end

    span_index
  end

  # Filter spans that are unlikely to match dictionary entries semantically
  # This reduces embedding API calls and semantic search overhead
  # Configuration is read from PubDic::EmbeddingServer
  def filter_spans_for_semantic(spans)
    min_length = PubDic::EmbeddingServer::MinSpanLength
    skip_numeric = PubDic::EmbeddingServer::SkipNumericSpans

    spans.select do |span|
      # Skip spans that are too short
      next false if span.length < min_length

      # Skip purely numeric spans
      next false if skip_numeric && span.match?(/\A[\d\.\-\+\,\s]+\z/)

      true
    end
  end

  # Batch get embeddings for all spans in span_index
  # Configuration is read from PubDic::EmbeddingServer (config/initializers/embedding_server.rb)
  def batch_get_embeddings(span_index)
    return if span_index.empty?

    # Pre-filter spans to reduce embedding requests
    all_spans = span_index.keys
    filtered_spans = filter_spans_for_semantic(all_spans)
    skipped_count = all_spans.size - filtered_spans.size

    batch_size = PubDic::EmbeddingServer::BatchSize
    parallel_threads = PubDic::EmbeddingServer::ParallelThreads

    Rails.logger.debug "Batch generating embeddings: #{filtered_spans.size} spans (#{skipped_count} filtered out, batch_size=#{batch_size}, threads=#{parallel_threads})"

    return if filtered_spans.empty?

    # Create batches from filtered spans
    batches = filtered_spans.each_slice(batch_size).to_a

    if batches.size > 1 && parallel_threads > 1
      fetch_embeddings_parallel(span_index, batches, parallel_threads)
    else
      fetch_embeddings_sequential(span_index, batches)
    end
  end

  def fetch_embeddings_sequential(span_index, batches)
    total_fetched = 0
    batches.each_with_index do |batch_spans, batch_idx|
      begin
        embeddings = EmbeddingServer.fetch_embeddings(batch_spans)
        batch_spans.each_with_index do |span, idx|
          span_index[span][:embedding] = embeddings[idx]
        end
        total_fetched += embeddings.size
        Rails.logger.debug "Embedding batch #{batch_idx + 1}/#{batches.size}: fetched #{embeddings.size} embeddings"
      rescue => e
        Rails.logger.warn "Failed to fetch embedding batch #{batch_idx + 1}: #{e.message}"
        # Continue with remaining batches, spans without embeddings will be skipped
      end
    end
    Rails.logger.debug "Successfully fetched #{total_fetched} embeddings total"
  end

  def fetch_embeddings_parallel(span_index, batches, parallel_threads)
    total_fetched = 0
    results_mutex = Mutex.new

    # Group batches for parallel processing
    batch_groups = batches.each_slice((batches.size.to_f / parallel_threads).ceil).to_a

    threads = batch_groups.map.with_index do |batch_group, group_idx|
      Thread.new do
        thread_results = {}
        thread_fetched = 0

        batch_group.each_with_index do |batch_spans, local_idx|
          begin
            embeddings = EmbeddingServer.fetch_embeddings(batch_spans)
            batch_spans.each_with_index do |span, idx|
              thread_results[span] = embeddings[idx]
            end
            thread_fetched += embeddings.size
          rescue => e
            Rails.logger.warn "Failed to fetch embedding batch (thread #{group_idx}, batch #{local_idx}): #{e.message}"
          end
        end

        { results: thread_results, fetched: thread_fetched }
      end
    end

    # Collect results from all threads
    threads.each do |thread|
      thread_data = thread.value
      results_mutex.synchronize do
        thread_data[:results].each do |span, embedding|
          span_index[span][:embedding] = embedding
        end
        total_fetched += thread_data[:fetched]
      end
    end

    Rails.logger.debug "Successfully fetched #{total_fetched} embeddings total (#{parallel_threads} threads)"
  end

  # Batch get identifiers for all spans from dictionaries
  # Uses batch semantic search and batch surface matching to reduce database round-trips
  def batch_get_identifiers(span_index, dictionaries)
    return if span_index.empty?

    # Filter sub_string_dbs to match the filtered dictionaries
    filtered_sub_string_dbs = @sub_string_dbs.select { |name, _| dictionaries.any? { |d| d.name == name } }

    # Step 1: Batch semantic search first (if enabled)
    # Uses temp tables with HNSW indexes for fast approximate nearest neighbor search
    semantic_results = {}
    if @semantic_threshold.present? && @semantic_threshold > 0
      # Build span_embeddings hash from span_index
      span_embeddings = {}
      span_index.each do |span, info|
        span_embeddings[span] = info[:embedding] if info[:embedding]
      end

      # Perform batch semantic search for each dictionary
      # Use temp table if available (faster HNSW-based search), otherwise fall back to regular search
      dictionaries.each do |dictionary|
        next unless dictionary.entries_num > 0

        temp_table_name = @semantic_temp_tables[dictionary.id]
        dict_results = if temp_table_name
          # Use temp table with dedicated HNSW index for fast semantic search
          dictionary.batch_search_semantic_temp(temp_table_name, span_embeddings, @semantic_threshold, [])
        else
          # Fall back to regular batch semantic search
          dictionary.batch_search_semantic(span_embeddings, @semantic_threshold, [])
        end

        dict_results.each do |span, entries|
          semantic_results[span] ||= []
          semantic_results[span].concat(entries)
        end
      end
    end

    # Step 2: Batch surface matching
    surface_results = batch_surface_match(span_index, dictionaries, filtered_sub_string_dbs)

    # Step 3: Combine results for each span
    span_index.each do |span, info|
      all_entries = surface_results[span] || []

      # Add semantic results
      if semantic_results[span].present?
        all_entries.concat(semantic_results[span])
        all_entries.uniq! { |r| r[:identifier] }
      end

      # Apply sorting based on search method
      if @superfluous
        all_entries.sort_by! { |e| -e[:score] }  # search_term_order: sort by score desc
      else
        # search_term_top: keep only entries with max score
        unless all_entries.empty?
          max_score = all_entries.max_by { |e| e[:score] }[:score]
          all_entries.delete_if { |e| e[:score] < max_score }
        end
      end

      info[:entries] = all_entries
    end
  end

  # Batch surface matching for all spans
  # Collects all unique norm2 values, queries entries in bulk, then matches back to spans
  def batch_surface_match(span_index, dictionaries, filtered_sub_string_dbs)
    results = Hash.new { |h, k| h[k] = [] }

    dictionaries.each do |dictionary|
      next if dictionary.entries_num == 0

      ssdb = filtered_sub_string_dbs[dictionary.name]
      threshold = @threshold || dictionary.threshold
      str_sim_method = dictionary.send(:str_sim)
      hash_method = dictionary.tags_exists? ? :to_result_hash_with_tags : :to_result_hash

      if threshold < 1
        # Collect all norm2s for this dictionary (with SimString expansion if enabled)
        # Build a mapping: norm2 -> [spans that need this norm2]
        norm2_to_spans = Hash.new { |h, k| h[k] = [] }

        span_index.each do |span, info|
          norm2 = info[:norm2]
          if @use_ngram_similarity && ssdb.present?
            expanded_norm2s = ssdb.retrieve(norm2)
            expanded_norm2s = [norm2] unless expanded_norm2s.present?
          else
            expanded_norm2s = [norm2]
          end

          expanded_norm2s.each do |n2|
            norm2_to_spans[n2] << { span: span, info: info }
          end
        end

        # Batch query: get all entries matching any of these norm2s
        all_norm2s = norm2_to_spans.keys
        next if all_norm2s.empty?

        # Query in batches to avoid overly large IN clauses
        all_norm2s.each_slice(1000) do |norm2_batch|
          entry_results = dictionary.entries.without_black.where(norm2: norm2_batch)
          entry_results = entry_results.includes(:tags) if dictionary.tags_exists?

          # Group entries by norm2 for fast lookup
          entries_by_norm2 = entry_results.group_by(&:norm2)

          # Match entries back to spans
          entries_by_norm2.each do |norm2, entries|
            span_infos = norm2_to_spans[norm2]
            next unless span_infos

            entries.each do |entry|
              entry_hash = entry.send(hash_method)

              span_infos.each do |span_info|
                span = span_info[:span]
                info = span_info[:info]

                score = str_sim_method.call(span, entry_hash[:label], info[:norm1], entry_hash[:norm1], info[:norm2], entry_hash[:norm2])
                if score >= threshold
                  results[span] << entry_hash.merge(score: score, dictionary: dictionary.name)
                end
              end
            end
          end
        end

        # Handle additional entries if they exist
        if dictionary.additional_entries_exists?
          all_norm2s.each_slice(1000) do |norm2_batch|
            additional_entries = dictionary.entries.additional_entries.where(norm2: norm2_batch)
            entries_by_norm2 = additional_entries.group_by(&:norm2)

            entries_by_norm2.each do |norm2, entries|
              span_infos = norm2_to_spans[norm2]
              next unless span_infos

              entries.each do |entry|
                entry_hash = entry.to_result_hash

                span_infos.each do |span_info|
                  span = span_info[:span]
                  info = span_info[:info]

                  score = str_sim_method.call(span, entry_hash[:label], info[:norm1], entry_hash[:norm1], info[:norm2], entry_hash[:norm2])
                  if score >= threshold
                    results[span] << entry_hash.merge(score: score, dictionary: dictionary.name)
                  end
                end
              end
            end
          end
        end
      else
        # Exact match path - batch query by label
        all_spans = span_index.keys

        all_spans.each_slice(1000) do |span_batch|
          entry_results = dictionary.entries.without_black.where(label: span_batch)

          # Group entries by label for fast lookup
          entries_by_label = entry_results.group_by(&:label)

          entries_by_label.each do |label, entries|
            entries.each do |entry|
              entry_hash = entry.to_result_hash.merge(score: 1, dictionary: dictionary.name)
              results[label] << entry_hash
            end
          end
        end
      end
    end

    results
  end

  # Generate denotations from pre-indexed spans with found identifiers
  # Single pass through span_index to create denotations
  def generate_denotations_from_spans(span_index, denotations)
    span_index.each do |span, info|
      next if info[:entries].empty?

      info[:entries].each do |entry|
        d = {
          span: {begin: info[:span_begin], end: info[:span_end]},
          obj: entry[:identifier],
          score: entry[:score],
          string: span,
          idx_token_final: info[:idx_token_final]
        }

        if @verbose
          d[:label] = entry[:label]
          d[:norm1] = entry[:norm1]
          d[:norm2] = entry[:norm2]
        end

        denotations << d
      end
    end
  end

end