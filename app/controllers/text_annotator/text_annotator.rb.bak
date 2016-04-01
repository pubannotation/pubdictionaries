#!/usr/bin/env ruby
require 'json'
require 'pathname'
require 'erb'

require File.join( File.dirname( __FILE__ ), 'query_builder' )
require File.join( File.dirname( __FILE__ ), 'post_processor' )
require File.join( File.dirname( __FILE__ ), 'text_to_trie' )


# Provide functionalities for text annotation.
# 
class TextAnnotator
  # Initialize the text annotator instance.
  #
  # * (string)  base_dic_name  - The name of a base dictionary for annotation.
  # * (integer) user_id        - The ID of the target user.
  #
  def initialize(base_dic_name, user)
    @base_dic_name = base_dic_name
    @user_id = (user and user.id)     # nil or user's id
    @options = { "min_tokens"       => 1,
                 "max_tokens"       => 6,
                 "matching_method"  => "approximate",     # "exact" or "approximate"
                 "threshold"        => 0.6,               # 0.0 <= "threshold" <= 1.0
                 "top_n"            => 0,                 # 0 for all results
               }
    
    # Load sub-workers.           
    @pgr       = POSTGRESQL_RETRIEVER.new(@base_dic_name, @user_id)
    if @pgr.dictionary_exist?(@base_dic_name) == true
      @ssr = SIMSTRING_RETRIEVER.new(@base_dic_name)
    else
      @ssr = nil
    end
    @qbuilder  = QUERY_BUILDER.new           
    @pproc     = POST_PROCESSOR.new
  end

  def dictionary_exist?(dic_name)
    return @pgr.dictionary_exist?(dic_name)
  end

  # Annotate an input text.
  #
  # * (hash) text  - Input text.
  # * (hash) opts  - A hash containing annotation options.
  #
  def annotate(text, opts)
    set_options(opts)

    if @options["matching_method"] == "exact"
      results = annotate_based_on_exact_string_matching(text)
    elsif @options["matching_method"] == "approximate"
      results = annotate_based_on_approximate_string_matching(text)
    else
      results = []
    end

    results 
  end

  # Return a hash of ID-LABEL pairs for an input list of IDs.
  #
  # * (array) ids  - A list of IDs
  # * (hash) opts  - A hash containing annotation options.
  #
  def ids_to_labels(ids, opts)
    results = {}

    ids.each do |id|
      results[id] = []

      entries = @pgr.get_entries_from_db(id, :uri)
      entries.each do |entry|
        results[id] << entry[:label]
      end
    end

    # results = { id1:[label1, label2, ...], id2:[...], ...}
    results
  end

  # Find ID list for each term. IDs are sorted based on the similarity
  # between an input term and a matched term.
  # 
  # * (list) terms - A list of terms.
  # * (hash) opts  - A hash containing annotation options.
  #                    1) opts["threshold"] : for query expansion.
  #                    2) opts["top_n"]     : for limiting the number of IDs.
  #
  def terms_to_entrylists(terms, opts)
    norm_opts  = @pgr.get_string_normalization_options
    # norm_opts value
    # { lowercased: dic[:lowercased], hyphen_replaced: dic[:hyphen_replaced], stemmed: dic[:stemmed] }
    trier      = TEXT_TO_TRIE.new
    expanded_terms  = {}
    expanded_IDs    = {}

    # 1. Perform query expansion for each input term based on a given threshold. The output 
    # is structured as follows.
    #
    #  expanded_terms = { 
    #    "an original input term 1" => [ 
    #      {
    #        :original_query  => "a normlaized input term 1"}
    #        :requested_query => "a term similar to :original_query",
    #        :offset          => a range object (absolute position within a given text),
    #        :sim             => 0.0~1.0
    #      },
    #      {
    #        :original_query  => "a normlaized input term 1"}
    #        :requested_query => "a term similar to :original_query",
    #        :offset          => a range object (absolute position within a given text),
    #        :sim             => 0.0~1.0
    #      },
    #      ...
    #    ],
    #    ...
    #  }
    #    
    terms.uniq.each do |term|
      offsets   = [(0...term.length)]
      norm_term = trier.normalize_term(
        term, norm_opts[:lowercased], norm_opts[:hyphen_replaced], norm_opts[:stemmed]
      )

      expanded_terms[term] = @qbuilder.expand_query(norm_term, offsets, opts["threshold"], @ssr, @pgr)

      # Keep only top n similar terms to speed up ID search.
      if opts["top_n"] > 0
        expanded_terms[term].sort! { |x, y| y[:sim] <=> x[:sim] }
        expanded_terms[term] = expanded_terms[term][0...opts["top_n"]]
      end
    end

    # 2. Get a list of IDs for each term.
    expanded_terms.each do |ori_term, sim_terms|
      expanded_IDs[ori_term] = []
      
      # 2.1. Get a list of DB entries for an original 
      sim_terms.each do |sim_term|
        entries = @pgr.get_entries_from_db(sim_term[:requested_query], :search_title)
        expanded_IDs[ori_term] += entries.collect do |entry|
          { uri: entry[:uri], sim: sim_term[:sim] }     # URI, Similarity
        end
      end
      

      #   The following two steps should be done above level since multiple dictionaries 
      # can affect the order.
      
      # 2.2. Sort the list based on the similarity value.
      # expanded_IDs[ori_term].sort! { |x, y| y[:sim] <=> x[:sim] }

      # 2.3. Sort the result.
      #
      # if opts["top_n"] > 0 and expanded_IDs[ori_term].size >= opts["top_n"]
      #   expanded_IDs[ori_term] = expanded_IDs[ori_term][0...opts["top_n"]]
      # end
    end

    expanded_IDs
  end


  ###################################
  #####     PRIVATE METHODS     #####
  ###################################
   private
  
  # Set options for text annotations.
  def set_options(opts)
    if not opts.nil?
      @options["min_tokens"]      = opts["min_tokens"] if not opts["min_tokens"].nil?
      @options["max_tokens"]      = opts["max_tokens"] if not opts["max_tokens"].nil?
      @options["matching_method"] = opts["matching_method"] if not opts["matching_method"].nil?
      @options["threshold"]       = opts["threshold"] if not opts["threshold"].nil?
      @options["top_n"]           = opts["top_n"] if not opts["top_n"].nil?
    end
  end

  # Text annotation based on exact string matching.
  def annotate_based_on_exact_string_matching(text)
    # Generate queries from an input text
    build_opts = { min_tokens: @options["min_tokens"],
             max_tokens: @options["max_tokens"] }
    norm_opts  = @pgr.get_string_normalization_options
    queries    = @qbuilder.build_queries(text, build_opts, norm_opts)

    # Retrieve the entries from PostgreSQL DB
    results = @pgr.retrieve( @qbuilder.change_format(queries) )

    # Apply post-processing methods
    if @options["top_n"] > 0
      results = @pproc.get_top_n(results, @options["top_n"])
    end
    results = @pproc.keep_last_one_for_crossing_boundaries(results)

    format_results(results)
  end

  # Text annotation based on approximate string matching.
  def annotate_based_on_approximate_string_matching(text)
    # Generate queries from an input text
    build_opts = { min_tokens: @options["min_tokens"],
             max_tokens: @options["max_tokens"] }
    norm_opts  = @pgr.get_string_normalization_options

    queries    = @qbuilder.build_queries(text, build_opts, norm_opts)

    # Perform query expansion using both the PG and SimString DBs.
    ext_queries = @qbuilder.expand_queries(queries, @options["threshold"], @ssr, @pgr)

    # Retrieve database entries
    results = @pgr.retrieve(ext_queries)

    # Applies post-processing methods
    if @options["top_n"] > 0
      results = @pproc.get_top_n(results, @options["top_n"])
    end
    results = @pproc.filter_based_on_simscore(results)
    results = @pproc.keep_last_one_for_crossing_boundaries(results)

    # Returns the results
    format_results(results)
  end

  # Reformat the results.
  def format_results(results)
    results_array = results.collect do |item|
      {
        span: {begin: item[:offset].begin, end: item[:offset].end},
        obj: item[:uri],
      }
    end

    results_array.uniq
  end

end


