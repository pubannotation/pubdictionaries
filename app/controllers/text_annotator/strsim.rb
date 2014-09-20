#!/usr/bin/env ruby
# encoding: UTF-8
Encoding.default_external="UTF-8"
Encoding.default_internal="UTF-8"


# Modified at 2013.10.03 


require 'set'


module Strsim
  # Obtain a set of letter n-grams in a string. 
  #   @param  str     The string.
  #   @param  n       The unit of n-grams.
  #   @param  be      true to generate n-grams that encode begin and end of a string.
  #
  #   - this algorithm is adopted from SimString.
  #
  def Strsim.ngrams (str, n = 3, be = true)
    mark = "\x01"

    # Prepares a source string for n-gram generation.
    src = ""
    if be == true
      # Append marks for begin/end of the string.
      src = mark*(n-1) + str + mark*(n-1)
    elsif str.length < n
      # Pad marks when the string is shorter than n.
      src = str + mark*(n-str.length)
    else
      src = str
    end

    # Collects unique n-grams and the number of occurrences of them.
    stat = Hash.new(0)
    (0...src.length-n+1).each { |i| stat[src[i...i+n]] += 1 }

    # Creates a set of n-grams
    ngram_set = Set.new
    stat.each do |ngram, count|
      (0...count).each do |i| 
        ngram_set.add("#{ngram}##{i}")
      end
    end

    ngram_set
  end


  def Strsim.cosine (str1, str2)
    ngrams1  = Strsim.ngrams(str1)
    ngrams2  = Strsim.ngrams(str2)

    return (ngrams1 & ngrams2).size.to_f / Math.sqrt(ngrams1.size * ngrams2.size)
  end

  def Strsim.overlap (str1, str2)
    ngrams1  = Strsim.ngrams(str1)
    ngrams2  = Strsim.ngrams(str2)
    
    return (ngrams1 & ngrams2).size.to_f / [ngrams1.size, ngrams2.size].min
  end

  def Strsim.jaccard (str1, str2)
    ngrams1  = Strsim.ngrams(str1)
    ngrams2  = Strsim.ngrams(str2)

    return (ngrams1 & ngrams2).size.to_f / (ngrams1 | ngrams2).size
  end

end



if __FILE__ == $0
  source_str  = "transforming growth factor 1"
  target_strs = [ "transforming growth factor 1",
                  "the transforming growth factor", 
                  "the transforming growth factor b",
                  "transforming growth factor",
                  "transforming growth factor b",
                  "transforming growth factor b (",
                ]

  puts "Cosine similarity:"
  target_strs.each do |target_str|
    puts "   #{source_str} vs. #{target_str} : #{Strsim.cosine(source_str, target_str)}"
  end

  puts "Jaccard index:"
  target_strs.each do |target_str|
    puts "   #{source_str} vs. #{target_str} : #{Strsim.jaccard(source_str, target_str)}"
  end

  puts "Overlap similarity:"
  target_strs.each do |target_str|
    puts "   #{source_str} vs. #{target_str} : #{Strsim.overlap(source_str, target_str)}"
  end
end
