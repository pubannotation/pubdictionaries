#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


# For a given text, creates a list of queries. If an option is given, expand the original 
# queries based on a specified threshold.


require 'triez'

require File.join( File.dirname( __FILE__ ), 'text_to_trie' )
require File.join( File.dirname( __FILE__ ), 'strsim' )


class QUERY_BUILDER
	include Strsim

	# Initialize the query builder instance.
	def initialize
		# Default values for query expansion
		@measure        = "jaccard"
		@threshold_gap  = 0.3           # Uses this to relax the threshold for PostgreSQL search 
	end
	
	# Create a series of normalized (!) queries from a document.
	# 
	# * text        - An input text.
	# * build_opts  - A hash containing options for generating queries from the input text.
	# * norm_opts   - A hash containing string normalization options for generating queries. 
	#
	def build_queries(text, build_opts, norm_opts)
		trier = TEXT_TO_TRIE.new( build_opts[:min_tokens],
								  build_opts[:max_tokens],
								  )
		
		# Queries are normalized.
		queries = trier.to_trie( text, 
		        				 norm_opts[:lowercased], 
		                       	 norm_opts[:hyphen_replaced], 
		                       	 norm_opts[:stemmed], 
		                       	)
		# queries  - A hash of key (the normalized query string) and value (the array of 
		#            offsets (range values)) pairs.
		queries
	end

	# Perform query expansion on normalized queries using both a base dictionary 
	# (from SimString) and a user dictionary (from PostgreSQL).
	# 
	# * (list)    queries   - A list of queries.
	# * (float)   threshold - A threshold for similarity search.
	# * (object)  ssr       - A SimString retriever object.
	# * (object)  pgr       - A Postgresql retriever object.
	#
	def expand_queries(queries, threshold, ssr, pgr)
		ext_queries = []
		queries.each do |q, offsets|
			basedic_new_queries = ssr.retrieve_similar_strings(q, @measure, threshold)
			
			userdic_new_queries = pgr.retrieve_similar_strings(q, relaxed_threshold(threshold)).delete_if do |item|
				basedic_new_queries.include?(item)
			end

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
						ext_queries << get_formatted_query(eq, q, offset, sim)
					end
				end
			end
		end
	
		#   @return  [ {:requested_query => string, :original_query => string, 
		#               :range => (begin...end), :sim => float}, ... ]
		ext_queries
	end

	# Change the format from queries to ext_queries
	def change_format(queries)
		ext_queries = [ ]
		queries.each do |q, offsets|
			offsets.each do |offset|
				ext_queries << get_formatted_query(q, q, offset, 1.0)
			end
		end

		ext_queries
	end


	###########################
	##### PRIVATE METHODS #####
	###########################	
	private


	# Get the formatted hash of annotation
	def get_formatted_query(ext_query, ori_query, offset, sim)
		{ requested_query: ext_query, original_query: ori_query, offset: offset, sim: sim }
	end

	# Because of the differece in the similarity calculation in the Postgresql and the SimString,
	# we use a relaxed threshold first and then use the searched entries having similarity scores
	# that are higher than the original threshold.
	def relaxed_threshold(threshold)
		if threshold > @threshold_gap
			relaxed_threshold = threshold - @threshold_gap
		else
			relaxed_threshold = threshold
		end
		relaxed_threshold
	end

end

