#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


=begin
	Performs post-processing on the annotation results such as n-best filtering,
	cross-boundary filtering, etc.
=end


# require 'set'
# require 'triez'
# require 'stemmify'
# require 'sequel'

# require File.join( File.dirname( __FILE__ ), '../simstring-1.0/swig/ruby/simstring' )
# require File.join( File.dirname( __FILE__ ), 'strsim' )


class POST_PROCESSOR

	# Post-processing #1: 
	#   - Keeps only n-best results on a single annotation (text span)
	def get_n_best(q2eqs, n)
		q2eqs.each_key do |ori_query|
			q2eqs[ori_query] = q2eqs[ori_query][0...n]
		end
		return q2eqs
	end

	# Post-processing #2: 
	def filter_based_on_simscore( results )
		# 1. sort it based on 1) matched string, 2) begin, 3) end, and 4) original query string
		sort_results_mrso( results )

		# 2. filter the results
		filtered = simscore_filter( results )

		return filtered
	end

	# Sort an array based on its :matched string, begina and end offsets, similarity score, and original query
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

	# Post-processing #3: 
	#   -
	#
	# TODO: brute-force. slow. we need a better algorithm
	def simscore_filter( unfolded )
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

	def overlap?( lhs, rhs )
		return lhs.include?( rhs.first) || rhs.include?( lhs.first )
	end

	# Post-processing #4: 
	#   - 
	def keep_last_one_for_crossing_boundaries( results )
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

	# Sorts a results array based on :begin and :end offset values
	def sort_results_offsets!( results )
		results.sort! do |a,b|
			if a[:range].begin != b[:range].begin
				a[:range].begin <=> b[:range].begin
			else
				a[:range].end <=> b[:range].end
			end
		end
	end

	# Checks if there is a crossing_boundary case or not
	def crossing_boundary?( pivot, target )
		x1, x2 = pivot[:range].begin, pivot[:range].end
		y1, y2 = target[:range].begin, target[:range].end

		if ((x1 < y1) and (y1 < x2 and x2 < y2)) or ((y1 < x1 and x1 < y2) and (y2 < x2)) 
			return true
		else
			return false
		end
	end

end

