#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"

#
# Annotate a free text using a PubDictionaries's dictionary.
#


require 'json'
require 'pathname'
require 'erb'

require File.join( File.dirname( __FILE__ ), 'retrieve_simstring_db' )
require File.join( File.dirname( __FILE__ ), 'retrieve_postgresql_db' )
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
	def initialize(base_dic_name, user_id)
		@base_dic_name = base_dic_name
		@user_id = user_id
		@options = { "min_tokens"       => 1,
		             "max_tokens"       => 5,
		             "matching_method"  => "exact",     # "exact" or "approximate"
		             "threshold"        => 0.6,         # 0.0 <= "threshold" <= 1.0
		             "top_n"            => 0,           # 0 for all results
		           }
		           
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
	# * (hash) ann   - A hash containing text for annotation (ann["text"]).
	# * (hash) opts  - A hash containing annotation options.
	#
	def annotate(ann, opts)
		set_options(opts)

		if @options["matching_method"] == "exact"
			results = annotate_based_on_exact_string_matching(ann)
		elsif @options["matching_method"] == "approximate"
			results = annotate_based_on_approximate_string_matching(ann)
		else
			results = []
		end

		results
	end

	# Return a hash of ID-LABEL pairs for an input list of IDs.
	#
	# * (list) ann  - A list of IDs (ann["ids"]).
	# * (hash) opts  - A hash containing annotation options.
	#
	def ids_to_labels(ann, opts)
		results = {}
		ann["ids"].each do |id|
			entries = @pgr.get_entries_from_db(id, :uri)
			if entries.empty?
				results[id] = []
			else
				# Assumes that each ID has a unique (representative) label 
				# results[id] = entries.collect do |x|
				# 	{"label" => x[:label]}
				# end
				results[id] = [ {"label" => entries[0][:label]} ]
			end
		end

		results
	end

	# Find ID list for each term. IDs are sorted based on the similarity
	# between an input term and a matched term.
	# 
	# * (list) ann   - A list of terms (ann["terms"]).
	# * (hash) opts  - A hash containing annotation options.
	#                    1) opts["threshold"] : for query expansion.
	#                    2) opts["top_n"]     : for limiting the number of IDs.
	#
	def terms_to_idlists(ann, opts)
		# 1. Find similar terms for each input term based on the given threshold.
		norm_opts  = @pgr.get_string_normalization_options
		trier      = TEXT_TO_TRIE.new
		
		exp_terms  = {}
		ann["terms"].uniq.each do |term|
			offsets   = [(0...term.length)]
 			norm_term = trier.normalize_term(term, 
 				norm_opts[:lowercased], norm_opts[:hyphen_replaced], norm_opts[:stemmed])

			exp_terms[term] = @qbuilder.expand_query(norm_term, offsets, opts["threshold"], @ssr, @pgr)

			# Keep only top n similar terms to speed up ID search.
			if opts["top_n"] > 0
				exp_terms[term].sort! { |x, y| y[:sim] <=> x[:sim] }
				exp_terms[term] = exp_terms[term][0...opts["top_n"]]
			end
		end

		# 2. Get a list of IDs for each term.
		exp_IDs = {}
	 	exp_terms.each do |ori_term, sim_terms|
	 		exp_IDs[ori_term] = []
	 		sim_terms.each do |sim_term|
	 			# Retrieve entries in both :entries and :new_entries except in :removed_entries.
	 			entries = @pgr.get_entries_from_db(sim_term[:requested_query], :search_title)
	 			exp_IDs[ori_term] = entries.collect do |x|
	 				{"uri" => x[:uri]}
	 			end

	 			# Stop the loop after havesting enough IDs.
	 			if opts["top_n"] > 0 and exp_IDs[ori_term].size >= opts["top_n"] 
	 				break
	 			end
	 		end
	 	end

	 	exp_IDs
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
	def annotate_based_on_exact_string_matching(ann)
		# Generate queries from an input text
		build_opts = { min_tokens: @options["min_tokens"],
					   max_tokens: @options["max_tokens"] }
		norm_opts  = @pgr.get_string_normalization_options
		queries    = @qbuilder.build_queries(ann["text"], build_opts, norm_opts)

		# Retrieve the entries from PostgreSQL DB
		results = @pgr.retrieve( @qbuilder.change_format(queries) )

		# Apply post-processing methods
		if @options["top_n"] > 0
			results = @pproc.get_top_n(results, @options["top_n"])
		end
		results = @pproc.keep_last_one_for_crossing_boundaries(results)

		format_anns(results)
	end

	# Text annotation based on approximate string matching.
	def annotate_based_on_approximate_string_matching(ann)
		# Generate queries from an input text
		build_opts = { min_tokens: @options["min_tokens"],
					   max_tokens: @options["max_tokens"] }
		norm_opts  = @pgr.get_string_normalization_options

		queries     = @qbuilder.build_queries(ann["text"], build_opts, norm_opts)
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
		format_anns(results)
	end

	# Create the annotation list (output) from the text annotation results.
	def format_anns(anns)
		return anns.collect do |item|
			{ begin:  item[:offset].begin, 
			  end:    item[:offset].end,
			  obj:    item[:uri],
			}
		end
	end

end


