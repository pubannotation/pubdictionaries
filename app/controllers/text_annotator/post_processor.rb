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

# require File.join( Rails.root, 'lib/simstring/swig/ruby/simstring')
# require File.join( File.dirname( __FILE__ ), 'strsim' )


class POST_PROCESSOR

	# Ppost-processing #1: 
	#     - Take only top n annotations with the highest scores for each original
	#   query.
	#
	#     Becareful that this process only applies to the annotations of an 
	#   original query having the same text span in text. A same expanded query 
	#   generated from two different original queries (i.e., "alpha 1 b 
	#   glycoprotein" from "alpha 1 b glycoprotein" and "related to alpha 1 b 
	#   glycoprotein".) will not be considered as a target in this process.
	#
	def get_top_n(anns, n)
		# Creates a hash based on the text spans.
		hashed_anns = {}
		anns.each do |item|
			(hashed_anns[item[:offset]] ||= []) << item
		end

		# Sorts each list of the hash in descend order, and takes n elements.
		hashed_anns.each do |key, value|
			value.sort! { |x, y| y[:sim] <=> x[:sim] }
			hashed_anns[key] = value.take(n)
		end

		# Return the results in the original format.
		hashed_anns.values.flatten
	end


	# Post-processing #2: 
	#     - Take only one annotation with the highest score for the queries
	#   having the text spans overlapped. Other overlapping queries will be 
	#   discarded.
	#
	def filter_based_on_simscore(anns)
		# 1. sort it based on 1) matched string, 2) begin, 3) end, and 4) original query string
		sort_results_mrso(anns)

		# 2. filter the results
		filtered = simscore_filter(anns)

		return filtered
	end

	# Sort an array based on its :matched string, begin and end offsets, similarity score, and original query
	def sort_results_mrso( anns )
		anns.sort! do |l, r| 
			if l[:requested_query] != r[:requested_query]
				l[:requested_query] <=> r[:requested_query]
			elsif l[:offset].begin != r[:offset].begin
				l[:offset].begin <=> r[:offset].begin
			elsif l[:offset].end != r[:offset].end
				l[:offset].end <=> r[:offset].end
			elsif l[:sim] != r[:sim]
				l[:sim] <=> r[:sim]
			else
				l[:original_query] <=> r[:original_query]
			end
		end
	end

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
				   (pivot[:requested_query] == cand[:requested_query]) and
				   overlap?( pivot[:offset], cand[:offset] ) and
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

	# Post-processing #3: 
	#     - Keeps the query which has the head word appearing at the rightmost position 
	#   among multiple queries that have cross boundaries.
	#
	def keep_last_one_for_crossing_boundaries( anns )
		sort_results_offsets!( anns )

		# use a pivot entity if it does not commit crossing boundary with another entity (target)
		# which follows the pivot entity
		new_anns = [ ]
		anns.each_index do |pidx|
			# results array is sorted. therefore, crossing boundary can be checked using only the
			# next entity.
			pivot  = anns[pidx]
			if pidx+1 == anns.length
				new_anns << pivot
			else
				b_cb = false
				(pidx+1...anns.length).each do |tidx|
					target = anns[tidx]
					if pivot[:offset].end <= target[:offset].begin
						break
					else
						if crossing_boundary?( pivot, target )
							b_cb = true
							break
						end
					end
				end
				
				if b_cb == false
					new_anns << pivot
				end
			end
		end

		return new_anns
	end

	# Sorts an anns array based on :begin and :end offset values
	def sort_results_offsets!( anns )
		anns.sort! do |a,b|
			if a[:offset].begin != b[:offset].begin
				a[:offset].begin <=> b[:offset].begin
			else
				a[:offset].end <=> b[:offset].end
			end
		end
	end

	# Checks if there is a crossing_boundary case or not
	def crossing_boundary?( pivot, target )
		x1, x2 = pivot[:offset].begin, pivot[:offset].end
		y1, y2 = target[:offset].begin, target[:offset].end

		if ((x1 < y1) and (y1 < x2 and x2 < y2)) or ((y1 < x1 and x1 < y2) and (y2 < x2)) 
			return true
		else
			return false
		end
	end

end

