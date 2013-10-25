#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


=begin
    Retrieves a list of similar strings for a given query string, one of five
  similarity measures, and the threshold (0.0 <= x <= 1.0).
=end


require File.join( File.dirname( __FILE__ ), '../../../../simstring-1.0/swig/ruby/simstring' )


class SIMSTRING_RETRIEVER

	# Initializes a retriever instance
	def initialize(dic_name, sim_measure="cosine", threshold=0.6)
		dbfile_path = File.join( File.dirname( __FILE__ ), "../../../../DictionaryManager/public/simstring_dbs", dic_name )
		begin 
			@db = Simstring::Reader.new(dbfile_path)
		rescue
			abort("Can not open a DB: #{dbfile_path}")
		end

		# 2. Sets a similarity measure and threshold
		if not set( sim_measure, threshold )
			abort("Fail to set the similarity measure and the threshold")
		end
	end


	# Retrieves a set of similar strings
	def retrieve_similar_strings(query, measure, threshold)
		set(measure, threshold)

		return @db.retrieve(query)
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
			$stderr.puts "Given threshold value is %d" % [ threshold ]
			return false
		end

		return true
	end


		
end