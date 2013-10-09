#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"

=begin
	Annotates a free text using a PubDictionaries's dictionary.
=end


require 'sinatra/base'
require 'json'
require 'pathname'
require 'erb'

require File.join( File.dirname( __FILE__ ), 'retrieve_simstring_db' )
require File.join( File.dirname( __FILE__ ), 'retrieve_postgresql_db' )
require File.join( File.dirname( __FILE__ ), 'query_builder' )


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
		qbuilder  = QUERY_BUILDER.new


		# Generates queries from an input text
		text        = get_param("text", annotation)
		build_opts  = { min_tokens: get_param("min_tokens", options),
					    max_tokens: get_param("max_tokens", options), 
					  }
		norm_opts   = pgr.get_string_normalization_options
		
		queries     = qbuilder.build_queries(text, build_opts, norm_opts)


		# Retrieves the entries from PostgreSQL DB
		pg_results = pgr.retrieve( qbuilder.change_format(queries) )


		# Returns the results
		annotation["denotations"] = [] unless annotation["denotations"]
		annotation["denotations"] = pg_results

		headers 'Content-Type' => 'application/json'
		body annotation.to_json
	end


	post '/rest_api/annotate_text/approximate_string_matching/?' do 
		annotation, options = get_data( params )

		ssr      = SIMSTRING_RETRIEVER.new(get_param("dictionary_name", options))
		pgr      = POSTGRESQL_RETRIEVER.new(get_param("dictionary_name", options))
		qbuilder = QUERY_BUILDER.new


		# Generates queries from an input text
		text        = get_param("text", annotation)
		build_opts  = { min_tokens: get_param("min_tokens", options),
					    max_tokens: get_param("max_tokens", options), 
					  }
		norm_opts   = pgr.get_string_normalization_options

		queries     = qbuilder.build_queries(text, build_opts, norm_opts)
		ext_queries = qbuilder.expand_queries(queries, get_param("threshold", options), ssr, pgr)


		# Retrieves database entries
		anns = pgr.retrieve(ext_queries)

	
		# Returns the results
		annotation["denotations"] = [] unless annotation["denotations"]
		annotation["denotations"] = anns

		headers 'Content-Type' => 'application/json'
		body annotation.to_json

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


