#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


=begin
	  For a given text, creates a list of queries. If an option is given, expand the original 
	queries based on a specified threshold.
=end


require 'triez'

require File.join( File.dirname( __FILE__ ), 'text_to_trie' )
require File.join( File.dirname( __FILE__ ), 'strsim' )


class QUERY_BUILDER
	include Strsim

	def initialize
		# For query expansion
		@measure        = "jaccard"
		@threshold_gap  = 0.3     # Uses this to relax the threshold for PostgreSQL search 
	end
	
	################################################################################
	#
	#   Creates a series of queries from a document.
	#
	#   @return  [ {:matched=>string, :original=>string, :range=>(begin...end), 
	#               :sim=>float}, ... ]
	#
	################################################################################
	def build_queries(text, build_opts, norm_opts)
		trier = TEXT_TO_TRIE.new( build_opts[:min_tokens],
								  build_opts[:max_tokens],
								  )
		
		queries = trier.to_trie( text, 
		        				 norm_opts[:lowercased], 
		                       	 norm_opts[:hyphen_replaced], 
		                       	 norm_opts[:stemmed], 
		                       	)

		queries
	end

	# Changes the format from queries to ext_queries
	def change_format(queries)
		ext_queries = [ ]
		queries.each do |q, offsets|
			offsets.each do |offset|
				ext_queries << get_formatted_query(q, q, offset, 1.0)
			end
		end

		ext_queries
	end

	# Get the formatted hash of annotation
	def get_formatted_query(ext_query, ori_query, offset, sim)
		{ matched: ext_query, original: ori_query, range: offset, sim: sim }
	end


	################################################################################
	#
	#   Performs query expansion using a base dictionary (from SimString) and a user
	# dictionary (from PostgreSQL).
	# 
	#   @return  [ {:matched=>string, :original=>string, :range=>(begin...end), 
	#               :sim=>float}, ... ]
	#
	################################################################################
	def expand_queries(queries, threshold, ssr, pgr)
		ext_queries = []
		queries.each do |q, offsets|
			basedic_new_queries = ssr.retrieve_similar_strings(q, @measure, threshold)
			userdic_new_queries = pgr.retrieve_similar_strings(q, relaxed_threshold(threshold))

			offsets.each do |offset|
				# Te original query is no longer necessary.
				# ext_queries << get_formatted_query(q, q, offset, Strsim.jaccard(q, q))

				basedic_new_queries.each do |eq|
					ext_queries << get_formatted_query(eq, q, offset, Strsim.jaccard(eq, q))
				end

				# Warning: 
				#
				#   PostgreSQL provides cosine similarity measure only. To avoid missing 
				# queries during query expansion, we use relaxed threshold first. Then, 
				# the search results will be re-ordered and filtered based on Jaccard 
				# similarity. The results that exceeds the original thresholds will be 
				# finally used.
				#
				userdic_new_queries.each do |eq|
					sim = Strsim.jaccard(eq, q)
					if sim > threshold
						ext_quereis << get_formatted_query(eq, q, offset, sim)
					end
				end
			end
		end
		ext_queries
	end

	def relaxed_threshold(threshold)
		if threshold > @threshold_gap
			relaxed_threshold = threshold - @threshold_gap
		else
			relaxed_threshold = threshold
		end
		relaxed_threshold
	end

end

