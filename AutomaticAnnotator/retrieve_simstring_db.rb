#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


=begin
 Program description

=end


require 'set'
require 'triez'
require 'stemmify'

require File.join( File.dirname( __FILE__ ), '../simstring-1.0/swig/ruby/simstring' )
require File.join( File.dirname( __FILE__ ), 'strsim' )


class SIMSTRING_RETRIEVER
	include Strsim

	# Initialize a retriever instance
	def initialize( db_name, sim_measure="cosine", threshold=0.6 )
		# 1. Open a SimString DB
		dbfile_path = File.join( File.dirname( __FILE__ ), "../DictionaryManager/public/simstring_dbs", db_name )
		begin 
			@db = Simstring::Reader.new(dbfile_path)
		rescue
			$stderr.puts "Can not open a DB!"       # $stderr.puts will be recorded in web-server's error log :-)
			$stderr.puts "   filepath: #{dbfile_path}"
		end

		# 2. Set a similarity measure and threshold
		if not set( sim_measure, threshold )
			$stderr.puts "sim_measure and/or threshold are not valid! Default values (cosine, 0.6) are used."
			set( "cosine", 0.6 )
		end
	end

	def set(measure, threshold)
		measure.downcase!

		if    "exact"   == measure
			@db.measure = Simstring::Exact	
		elsif "cosine"  == measure
			@db.measure = Simstring::Cosine	
		elsif "dice"    == measure
			@db.measure = Simstring::Dice
		elsif "jaccard" == measure
			@db.measure = Simstring::Jaccard
		elsif "overlap" == measure
			@db.measure = Simstring::Overlap
		else
			$stderr.puts "Not recognizable option: %s" % [ measure ]
			return false
		end

		if threshold > 0.0  and threshold <= 1.0
			@db.threshold = threshold
		else
			puts "Given threshold value is %d" % [ threshold ]
			return false
		end

		return true
	end

	# Retrieves a set of similar strings
	def retrieve_similar_strings(query, threshold)
		set("cosine", threshold)

		return @db.retrieve(query)
	end
		
end