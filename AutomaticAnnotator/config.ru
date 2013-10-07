#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"

=begin
	Program description:

=end


require 'sinatra/base'
require 'json'
require 'pathname'
require 'erb'

require File.join( File.dirname( __FILE__ ), 'text_to_trie' )
require File.join( File.dirname( __FILE__ ), 'retrieve_simstring_db' )
require File.join( File.dirname( __FILE__ ), 'retrieve_postgresql_db' )
require File.join( File.dirname( __FILE__ ), 'query_expander' )


class PubDicAnnotation_WS < Sinatra::Base
	configure do
		# default values
		set :defaults, { "text" => "No text input is given", 
		                 "dictionary_name" => "default_dictionary",
		                 "min_tokens" => 1,
		                 "max_tokens" => 5,
		               }
	end

	get '/rest_api/?' do
		erb :index
	end

	post '/rest_api/annotate_text/exact_string_matching/?' do 
		annotation, options = get_data( params )

		pgr       = POSTGRESQL_RETRIEVER.new(get_param("dictionary_name", options))
		norm_opts = pgr.get_string_normalization_options()
		
		
		# Creates a series of queries from an input document using a TRIE
		qwo = build_queries_with_offsets(annotation, options, norm_opts)
		converted_qwo = convert_data(qwo)

		# Retrieves the entries from PostgreSQL DB
		pg_results = pgr.retrieve(converted_qwo)

		# Returns the results
		annotation["denotations"] = [] unless annotation["denotations"]
		annotation["denotations"] = pg_results

		headers 'Content-Type' => 'application/json'
		body annotation.to_json
	end

	post '/rest_api/annotate_text/approximate_string_matching/?' do 
		annotation, options = get_data( params )

		ssr   = SIMSTRING_RETRIEVER.new(get_param("dictionary_name", options))
		pgr   = POSTGRESQL_RETRIEVER.new(get_param("dictionary_name", options))
		qexp  = QUERY_EXPANDER.new(ssr, pgr)

		norm_opts = pgr.get_string_normalization_options()
		
		
		# Creates a series of queries from an input document using a TRIE
		#   @return  qos[query]  = [(begin1...end1), (begin2...end2), ...]
		qwo = build_queries_with_offsets(annotation, options, norm_opts)

		# Performs query expansion using both base dictionary and user dictionary
		#   @return  [ {:matched=>string, :original=>string, :range=>(begin...end), :sim=>float}, ... ]
		e_qwo = qexp.expand_queries(qwo, get_param("threshold", options))

		# Retrieves database entries
		anns = pgr.retrieve(e_qwo)

	
		# Returns the results
		annotation["denotations"] = [] unless annotation["denotations"]
		annotation["denotations"] = anns

		headers 'Content-Type' => 'application/json'
		body annotation.to_json

	end


	# TODO: same to the function in query_expander.rb
	def convert_data(qos)
		results = [ ]
		qos.each do |query, offsets|
			offsets.each do |offset|
				results << { :matched  => query, 
							 :original => query,
		 	        	     :range    => offset,
							 :sim      => 1.0,
						   }	
			end
		end
		return results
	end

	#   Creates a series of queries from a document and returns a hash consisting of
	# a key (a query) and a value (a list of offsets where the query appears).
	#   @return  { query1:[(begin...end), (begin...end), ...], ... }
	#
	def build_queries_with_offsets(annotation, options, norm_opts)
		trier = TEXT_TO_TRIE.new( get_param("min_tokens", options), 
		                          get_param("max_tokens", options), 
								  )
		queries_with_offsets = trier.to_trie( get_param("text", annotation), 
		                       				  norm_opts[:lowercased], 
		                       				  norm_opts[:hyphen_replaced], 
		                       				  norm_opts[:stemmed], 
		                       				)
		return queries_with_offsets
	end

	def get_data( params )
		annotation = { }
		if not params[:annotation].nil?
			annotation = JSON.parse( params[:annotation] )
		end
	
		options = { }
		if not params[:options].nil?
			options = JSON.parse( params[:options] )
		end

		return annotation, options
	end

	def get_param( opt_name, options )
		if options.has_key?( opt_name )
			return options[opt_name]
		else
			return settings.defaults[opt_name]
		end
	end

	def build_pgdb_output( data, results, errorno )
		output = { "parameters" => { "db_name" => data["db_name"],
									 "tax_ids" => data["tax_ids"] 
								   },
				   "results" => results,
				 }.to_json

		return output
	end
end


run PubDicAnnotation_WS.new


