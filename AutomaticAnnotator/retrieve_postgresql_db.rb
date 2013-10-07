#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


=begin
	Program description:

=end


require 'pathname'
require 'fileutils'
require 'set'
require 'sequel'


class POSTGRESQL_RETRIEVER
	include Strsim

	def initialize(dic_name)
		# 1. open a database connection
		adapter  = 'postgres'
		host     = 'localhost'
		port     = 5432
		db       = 'unicorn_db_app1'
		user     = 'nlp'
		passwd   = 'dbcls_nlp_unicorn_development'

		# TODO: exception handling here...
		@db            = Sequel.connect( :adapter => adapter, :host => host, :port => port, 
			                         :database => db, :user => user, :password => passwd )
		@dic_name      = dic_name
		@results_cache = { }
	end

	# Returns the string normalization options used to create a dictionary
	def get_string_normalization_options
		dic = @db[:dictionaries].where(:title => @dic_name).first
		return { lowercased: dic[:lowercased], hyphen_replaced: dic[:hyphen_replaced], stemmed: dic[:stemmed] }
	end


	# API-01: 
	#   Retrieves entries which are similar to the query based on the given threshold.
	def retrieve_similar_strings(query, threshold)
		basedic_id  = @db[:dictionaries].select(:id).where(:title => @dic_name).first[:id]
		userdic_id  = @db[:user_dictionaries].select(:id).where(:dictionary_id => basedic_id).first[:id]
		simfun      = Sequel.function(:similarity, :search_title, query)
		
		# Extracts a list of similar entry names compared to the query
		#     - compared to @db.fetch command below, this is very slow.
		# ds = @db[:new_entries].where(:user_dictionary_id => userdic_id).where(simfun >= threshold).select_append(simfun).order(Sequel.desc(simfun), :title)
		# $stdout.puts @db[:new_entries].select(:title).where(:user_dictionary_id => userdic_id).where(simfun >= threshold).inspect
		ds = @db[:new_entries].where(:user_dictionary_id => userdic_id).where(simfun >= threshold)

		# Setting set_limit first and use % in where clause greatly accellerates the 
		# search speed. However, it is unclear whether set_limit can cause a problem when a db search
		# request comes while another one is on-going.
		# @db.transaction do
		# 	ds = @db.fetch("SELECT set_limit(#{threshold}); 
		# 					SELECT *, similarity(title, :query) FROM entries 
		# 					WHERE title % :query
		# 					ORDER BY similarity DESC, title", 
		# 			  		:query => query, 
		# 			  		)
		# end
		
		results = []
		ds.all.each do |row| 
			$stdout.puts "Row: #{row.inspect}"
			results << row[:view_title] 
		end
		# $stdout.puts tmp.inspect
		results.uniq
	end


	# Retrieves entries from DB for the queries generated from document
	def retrieve(anns)		
		results = anns.collect do |ann|
			if @results_cache.include? ann[:matched]
				get_from_cache(ann[:matched], ann[:range])
			else
				sim = Strsim.cosine(ann[:original], ann[:matched])
				search_db(ann[:matched], ann[:range], sim)
			end
		end

		results.reject { |ann| ann == [] }
	end
	

	# Gets the result from cache
	def get_from_cache(query, offset)
		@results_cache[query].collect do |value|
			results << { :begin => offset.begin, :end => offset.end, :obj => value[:obj] }
		end
	end

	# Searches the database
	def search_db(query, offset, sim)
		@results_cache[query] = []

		results  = get_entries_from_db(query)
		outputs  = build_output(query, results, sim, offset)

		return outputs
	end

	# Gets entries from DB that have similar names to the query string
	def get_entries_from_db(query)
		results   = [ ]
		# gid_history  = Set.new

		dic_id       = @db[:dictionaries].select(:id).where(:title => @dic_name).first[:id]
		user_dic_id  = @db[:user_dictionaries].select(:id).where(:dictionary_id => dic_id).first[:id]
		
		removed_entry_idlist = @db[:removed_entries].select(:entry_id).where(:user_dictionary_id => user_dic_id)

		# Retrieves the entries for a given query except those are marked as removed
		ds = @db[:entries].where(:dictionary_id => dic_id).where(:search_title => query).exclude(:id => removed_entry_idlist)
		ds.all.each do |row|
			results << { label: row[:label], uri: row[:uri], title: row[:view_title] }

			# use if the same gene id has not been found yet
			# if not gid_history.include?( row[:uri] )
			# 	results << { label: row[:label], uri: row[:uri], title: row[:title] }
			# 	gid_history.add( row[:uri] )
			# end
		end

		# Adds newly added entries by a user
		ds = @db[:new_entries].where(:user_dictionary_id => user_dic_id).where(:search_title => query)
		ds.all.each do |row|
			results << { label: row[:label], uri: row[:uri], title: row[:view_title] }

		# 	if not gid_history.include?( row[:uri] )
		# 		results << { label: row[:label], uri: row[:uri], title: row[:title] }
		# 		gid_history.add( row[:uri] )
		# 	end
		end

		return results
	end

	# Creates output data from the PostgreSQL search results
	def build_output(query, results, sim, offset)
		outputs = results.collect do |value|
			# Gets the official_symbol and tax_id in :label column
			items            = value[:label].split('|')
			official_symbol  = items[0]
			tax_id           = Integer( items[1] ) 
		
			# Updates the result cache
			@results_cache[ query ] << { :obj => "#{value[:uri]}:#{official_symbol}:#{tax_id}:#{sim}" }
			
			# Adds the search result
			{ :requested_query => query,
			  :begin => offset.begin, :end => offset.end,
			  :obj => "#{value[:uri]}:#{official_symbol}:#{tax_id}:#{sim}",
			  }
		end

		return outputs
	end
end


