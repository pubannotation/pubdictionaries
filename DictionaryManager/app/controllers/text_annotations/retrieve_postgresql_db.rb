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
require File.join(File.dirname( __FILE__ ), "strsim")


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


	# API #1: 
	#   - Retrieves a list of normalized queries that are similar to the original normalized
	#  query based on PostgreSQL's trigram search (pg_trgm extension).
	#
	def retrieve_similar_strings(query, threshold)
		# TODO: refactoring this...
		basedic_id = -1
		userdic_id = -1

		basedic = @db[:dictionaries].select(:id).where(:title => @dic_name).all
		if basedic.empty?
			return []
		else
			basedic_id  = basedic.first[:id]

			userdic  = @db[:user_dictionaries].select(:id).where(:dictionary_id => basedic_id).all
			if userdic.empty?
				return []
			else
				userdic_id  = userdic.first[:id]
			end
		end

		simfun      = Sequel.function(:similarity, :search_title, query)
		
		# Extracts a list of similar entry names compared to the query
		#     - compared to @db.fetch command below, this is very slow.
		# ds = @db[:new_entries].where(:user_dictionary_id => userdic_id).where(simfun >= threshold).select_append(simfun).order(Sequel.desc(simfun), :title)
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
			results << row[:search_title] 
		end

		results.uniq
	end


	# API #2:
	#   - For each annotation, extract URI and label information from PostgreSQL db and add them 
	#   to the annotation.
	#
	def retrieve(anns)		
		results = anns.collect do |ann|
			if @results_cache.include? ann[:requested_query]
				get_from_cache(ann[:requested_query], ann[:original_query], ann[:offset], ann[:sim])
			else
				search_db(ann[:requested_query], ann[:original_query], ann[:offset], ann[:sim])
			end
		end

		results.reject { |ann| ann == [] }
		
		results.flatten
	end
	

	# Gets the result from the results cache
	def get_from_cache(query, ori_query, offset, sim)
		@results_cache[query].collect do |res|
			build_output(query, ori_query, res, sim, offset)
		end
	end

	# Searches the database
	def search_db(query, ori_query, offset, sim)
		@results_cache[query] = []
		
		results = get_entries_from_db(query, :search_title)
		results.collect do |res|
			data = build_output(query, ori_query, res, sim, offset)
			
			# Puts the data into the results cache
			@results_cache[ query ] << data

			# Uses the data to build results array
			data
		end
	end

	# Gets entries from DB that have similar names to the query string
	def get_entries_from_db(query, target_column)
		results   = [ ]
		# gid_history  = Set.new

		# TODO: error handling, refactoring
		dic     = @db[:dictionaries].select(:id).where(:title => @dic_name).all
		dic_id  = -1
		if dic.empty?
			return [ ]
		else
			dic_id = dic.first[:id]
		end

		user_dic              = @db[:user_dictionaries].select(:id).where(:dictionary_id => dic_id).all
		user_dic_id           = -1
		removed_entry_idlist  = []
		if not user_dic.empty?
			user_dic_id           = user_dic.first[:id]
			removed_entry_idlist  = @db[:removed_entries].select(:entry_id).where(:user_dictionary_id => user_dic_id).all
		end
		
		# Retrieves the entries for a given query except those are marked as removed
		ds = @db[:entries].where(:dictionary_id => dic_id).where(target_column => query).exclude(:id => removed_entry_idlist)
		ds.all.each do |row|
			results << { label: row[:label], uri: row[:uri], title: row[:view_title] }

			# use if the same gene id has not been found yet
			# if not gid_history.include?( row[:uri] )
			# 	results << { label: row[:label], uri: row[:uri], title: row[:title] }
			# 	gid_history.add( row[:uri] )
			# end
		end

		# Adds newly added entries by a user
		if user_dic.empty?
			ds = @db[:new_entries].where(:user_dictionary_id => user_dic_id).where(target_column => query)
			ds.all.each do |row|
				results << { label: row[:label], uri: row[:uri], title: row[:view_title] }

			# 	if not gid_history.include?( row[:uri] )
			# 		results << { label: row[:label], uri: row[:uri], title: row[:title] }
			# 		gid_history.add( row[:uri] )
			# 	end
			end
		end

		return results
	end

	# Creates an output data
	def build_output(query, ori_query, res, sim, offset)
		return { requested_query: query, 
			     original_query:  ori_query, 
			     offset:          offset,
				 uri:             res[:uri], 
				 label:           res[:label], 
				 sim:             sim,
				}
	end

end


