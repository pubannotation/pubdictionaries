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
	end

	# Annotate an input text.
	#
	# * ann   - A hash containing text for annotation (ann["text"]).
	# * opts  - A hash containing annotation options.
	#
	def annotate(ann, opts)
		set_options(opts)

		if @options["matching_method"] == "exact"
			results = annotate_based_on_exact_string_matching(ann)
		elsif @options["matching_method"] == "approximate"
			results = annotate_based_on_approximate_string_matching(ann)
		else
			ann["denotations"] = []
			results = ann
		end

		results
	end

	# Return a hash of ID-LABEL pairs for an input list of IDs.
	#
	# * ann  - A list of IDs.
	#
	def id_to_label(ann, opts)
		pgr = POSTGRESQL_RETRIEVER.new(@base_dic_name, @user_id)

		results = {}
		ann["ids"].each do |id|
			# Assumes that each ID has a unique label
			entries = pgr.get_entries_from_db(id, :uri)
			if entries.empty?
				results[id] = nil
			else
				results[id] = entries[0][:label]	
			end
		end

		ann["denotations"] = [] unless ann["denotations"]
		ann["denotations"] = results
		
		ann
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
		qbuilder  = QUERY_BUILDER.new
		pgr       = POSTGRESQL_RETRIEVER.new(@base_dic_name, @user_id)
		pproc     = POST_PROCESSOR.new


		# Generate queries from an input text
		build_opts = { min_tokens: @options["min_tokens"],
					   max_tokens: @options["max_tokens"] }
		norm_opts  = pgr.get_string_normalization_options
		
		queries = qbuilder.build_queries(ann["text"], build_opts, norm_opts)


		# Retrieve the entries from PostgreSQL DB
		results = pgr.retrieve( qbuilder.change_format(queries) )
		

		# Apply post-processing methods
		if @options["top_n"] > 0
			results = pproc.get_top_n(results, @options["top_n"])
		end
		results = pproc.keep_last_one_for_crossing_boundaries(results)


		# Return the results
		ann["denotations"] = [] unless ann["denotations"]
		ann["denotations"] = format_anns(results)

		ann
	end

	# Text annotation based on approximate string matching.
	def annotate_based_on_approximate_string_matching(ann)
		qbuilder  = QUERY_BUILDER.new
		ssr       = SIMSTRING_RETRIEVER.new(@base_dic_name)
		pgr       = POSTGRESQL_RETRIEVER.new(@base_dic_name, @user_id)
		pproc     = POST_PROCESSOR.new


		# Generate queries from an input text
		build_opts = { min_tokens: @options["min_tokens"],
					   max_tokens: @options["max_tokens"] }
		norm_opts  = pgr.get_string_normalization_options

		queries     = qbuilder.build_queries(ann["text"], build_opts, norm_opts)
		ext_queries = qbuilder.expand_queries(queries, @options["threshold"], ssr, pgr)


		# Retrieve database entries
		results = pgr.retrieve(ext_queries)
		

		# Applies post-processing methods
		if @options["top_n"] > 0
			results = pproc.get_top_n(results, @options["top_n"])
		end
		results = pproc.filter_based_on_simscore(results)
		results = pproc.keep_last_one_for_crossing_boundaries(results)

	
		# Returns the results
		ann["denotations"] = [] unless ann["denotations"]
		ann["denotations"] = format_anns(results)

		ann
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


