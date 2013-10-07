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
	def initialize( db_name, sim_measure=Simstring::Cosine, threshold=0.6 )
		# 1. Open a SimString DB
		dbfile_path = File.join( File.dirname( __FILE__ ), "../DictionaryManager/public/simstring_dbs", db_name )
		begin 
			@db = Simstring::Reader.new(dbfile_path)
		rescue
			$stderr.puts "Can not open a DB!"       # $stderr.puts will be recorded in web-server's error log :-)
			$stderr.puts "   filepath: #{dbfile_path}"
		end

		# 2. Set a similarity measure and threshold
		if not set_sim_params( sim_measure, threshold )
			$stderr.puts "sim_measure and/or threshold are not valid! Default values (cosine, 0.6) are used."
			set_sim_params( Simstring::Jaccard, 0.6 )
		end
	end

	def set_sim_params( sim_measure, threshold )
		sim_measure = sim_measure.downcase

		if    "exact"   == sim_measure
			@db.measure = Simstring::Exact	
		elsif "cosine"  == sim_measure
			@db.measure = Simstring::Cosine	
		elsif "dice"    == sim_measure
			@db.measure = Simstring::Dice
		elsif "jaccard" == sim_measure
			@db.measure = Simstring::Jaccard
		elsif "overlap" == sim_measure
			@db.measure = Simstring::Overlap
		else
			$stderr.puts "Not recognizable option: %s" % [ sim_measure ]
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
			
	# API-01:
	#
	#     Retrieve similar strings for all possible substrings of a given input text
	#
	def expand_queries( queries_with_offsets, n_best )
		# Search the simstring db using every substring in the tried text as a query
		results = search_similar_strings( queries_with_offsets, n_best )

		# filter the search results based on similarity score
		results = filter_based_on_simscore( results )

		# handle cross boundary cases
		results = handle_cross_boundaries( results )

		# results = [ {match: string, range: begin...end, original: string, sim: float }, ... ]
		return results
	end


	## Search similar strings for each query and create a list of them
	def search_similar_strings( queries_with_offsets, n_best )
		results = [ ]
		
		queries_with_offsets.each do |query, offsets|
			if n_best > 0
				simstrs = get_n_or_more_results( query, n_best )   # simstrs.length <= n is possible!
			else
				simstrs = @db.retrieve(query)
			end
			
			if not simstrs.empty?
				# use only n simstrs if n > 0 
				if n_best > 0 and simstrs.length > n_best
					simstrs = get_top_n(simstrs, query, n_best)
				end
				
				# retrieve offsets of the query at multiple positions in the text
				offsets.each do |offset|
					simstrs.each do |simstr|
						results << { :matched  => simstr, 
						             # :range    => (offset[0]...offset[1]),
						             :range    => offset,
									 :original => query,
									 :sim      => Strsim.jaccard( simstr, query ) 
								   }
					end
				end
			end
		end

		return results
	end

	### 
	def get_n_or_more_results( query, n_best )
		old_threshold = @db.threshold
		
		var_thresholds = [0.8, 0.6, 0.5]
		simstrs = [ ]
		var_thresholds.each do |th|
			@db.threshold = th
			simstrs = @db.retrieve(query)
			if simstrs.length >= n_best
				break
			end
		end

		@db.threshold = old_threshold

		return simstrs
	end

	###
	def get_top_n( simstrs, query, n )
		# calcualte similarity scores
		strsim_lst = [ ]
		simstrs.each do |simstr|
			strsim_lst << [simstr, Strsim.jaccard(simstr, query)]
		end

		# sort based on similarity scores
		strsim_lst.sort! do |l, r|
			r[1] <=> l[1]     # descending order sorting
		end

		# return new list
		top_n = [ ]
		(0...n).each do |idx|
			top_n << strsim_lst[idx][0]
		end

		return top_n
	end


	## Filter inputs based on the overlapped searched strings 
	def filter_based_on_simscore( results )
		# 1. sort it based on 1) matched string, 2) begin, 3) end, and 4) original query string
		sort_results_mrso( results )

		# 2. filter the results
		filtered = simscore_filter( results )

		return filtered
	end

	### Sort an array based on its :matched string, begina and end offsets, similarity score, and original query
	def sort_results_mrso( results )
		results.sort! do |l, r| 
			if l[:matched] != r[:matched]
				l[:matched] <=> r[:matched]
			elsif l[:range].begin != r[:range].begin
				l[:range].begin <=> r[:range].begin
			elsif l[:range].end != r[:range].end
				l[:range].end <=> r[:range].end
			elsif l[:sim] != r[:sim]
				l[:sim] <=> r[:sim]
			else
				l[:original] <=> r[:original]
			end
		end
	end

	###
	def simscore_filter( unfolded )
		# TODO: brute-force. slow. we need better algorithm
		filtered = [ ]
		(0...unfolded.size).each do |pos1|
			pivot     = unfolded[pos1]
			b_highest = true

			# check if the pivot has the highest sim. value or not
			(0...unfolded.size).each do |pos2|
				cand    = unfolded[pos2]
					
				if (pos1 != pos2) and 
				   (pivot[:matched] == cand[:matched]) and
				   overlap?( pivot[:range], cand[:range] ) and
				   (pivot[:sim] < cand[:sim])
					b_highest = false
					break
				end
			end

			if b_highest == true
				filtered << pivot
			end
		end

		return filtered
	end

	####
	def overlap?( lhs, rhs )
		return lhs.include?( rhs.first) || rhs.include?( lhs.first )
	end


	## Keep the last one if crossing boundary appears
	def handle_cross_boundaries( results )
		sort_results_offsets!( results )

		# use a pivot entity if it does not commit crossing boundary with another entity (target)
		# which follows the pivot entity
		new_results = [ ]
		results.each_index do |pidx|
			# results array is sorted. therefore, crossing boundary can be checked using only the
			# next entity.
			pivot  = results[pidx]
			if pidx+1 == results.length
				new_results << pivot
			else
				b_cb = false
				(pidx+1...results.length).each do |tidx|
					target = results[tidx]
					if pivot[:range].end <= target[:range].begin
						break
					else
						if crossing_boundary?( pivot, target )
							b_cb = true
							break
						end
					end
				end
				
				if b_cb == false
					new_results << pivot
				end
			end
		end

		return new_results
	end

	### Sort a results array based on :begin and :end offset values
	def sort_results_offsets!( results )
		results.sort! do |a,b|
			if a[:range].begin != b[:range].begin
				a[:range].begin <=> b[:range].begin
			else
				a[:range].end <=> b[:range].end
			end
		end
	end

	###
	def crossing_boundary?( pivot, target )
		x1, x2 = pivot[:range].begin, pivot[:range].end
		y1, y2 = target[:range].begin, target[:range].end

		if ((x1 < y1) and (y1 < x2 and x2 < y2)) or ((y1 < x1 and x1 < y2) and (y2 < x2)) 
			return true
		else
			return false
		end
	end


	# API-02:
	#
	#     Retrieve similar strings for user-defined text annotations
	#
	def retrieve_simstrings_user_anns1( text, user_anns, target_classes, n_best, bCaseInsensitive, bReplaceHyphen, bStemming )
		# Create substrings from a text
		qs = generate_queries_user_anns1( text, user_anns, target_classes, bCaseInsensitive, bReplaceHyphen, bStemming )
	
		# Search the simstring db using every substring in the tried text as a query
		results = search_similar_strings( qs, n_best )

		return results
	end


	## Generate queries without any constraints on substring length or stop words
	def generate_queries_user_anns1( text, text_anns, target_classes, bCaseInsensitive, bReplaceHyphen, bStemming )
		queries = { }
		
		text_anns.each do |ann|
			beg_offset      = ann["begin"]
			end_offset      = ann["end"]
			semantic_class  = ann["class"]

			if target_classes.include?(semantic_class)
				q = text[beg_offset...end_offset]

				# use a stemmed substring 
				#     warning) substr.length may or may not same to end_offset-beg_offset
				$stderr.puts q
				if bStemming == true
					offsets = tokenize( q )     # relative offsets in q
					q = ""
					offsets.each_index do |tidx|
						if tidx > 0
							q += text[ beg_offset+offsets[tidx-1][:end]...beg_offset+offsets[tidx][:begin] ]
						end
						q += text[ beg_offset+offsets[tidx][:begin]...beg_offset+offsets[tidx][:end] ].stem
					end
				end
				$stderr.puts "  " + q

				# string normalization
				if bCaseInsensitive == true
					q.downcase!
				end
				if bReplaceHyphen == true
					q.gsub!( "-", " " )
				end
					
				if not queries.has_key?(q)
					queries[ q ] = [ [beg_offset, end_offset] ]
				else
					queries[ q ] << [beg_offset, end_offset]
				end
			end
		end
		
		return queries
	end

	## 
	def tokenize( text )
		# 1. tokenize an input text
		tokens = text.split(/\s|(\W|_)/).reject { |t| t.empty? }   # does not match unicode, check \p{word}
	
		# 2. find the index of each token
		token_indices = [ ]
		abs_pos = 0
		tokens.each do |t|
			cur_pos = text.index( t, abs_pos )
			token_indices << {:begin=>cur_pos, :end=>cur_pos + t.length}
			abs_pos = cur_pos + t.length 
		end

		return token_indices
	end
	


	def stopwords?( query )
		if @STOP_WORDS.include?(query.downcase) or
		   query.length <= 1 or                       # a one character string is a stop word
		   query.downcase.start_with?('the ', 'a ', 'an ') or
		   query.start_with?('-', '(', ')', ',', '.') or
		   query.end_with?('-', '(', ')', ',', '.') or
		   /^[\d.]+$/.match( query ) or               # a numeric string is a stop word or
		   /^\d[a-zA-Z]$/.match( query )
			return true
		else
			return false
		end
	end

end



def print_info( query, db, simm, th, minsubstrlen, maxsubstrlen )
	puts "This is a sample query"
	puts " Qeury: " + query
	puts " TargetDB: " + db
	puts " Similarity measure:"
	puts "     Measure: " + simm.to_s()
	puts "     Threshold: " + th.to_s()
	puts "     Minimum substring length: " + minsubstrlen.to_s()
	puts "     Maximum substring length: " + maxsubstrlen.to_s()
end 

def print_result( results )
	results.sort! do |a,b|
		if a[:begin] != b[:begin]
			a[:begin] <=> b[:begin]
		else
			a[:end] <=> b[:end]
		end
	end

	results.each do |r|	
		puts ":begin - %d, :end - %d, :original - %s" % [ r[:begin], r[:end], r[:original] ]
		puts "   :matched = [ %s ] " % [ r[:matched].join(", ") ]
	end
end



if __FILE__ == $0
	puts "This is not a stand-alone program."

end
