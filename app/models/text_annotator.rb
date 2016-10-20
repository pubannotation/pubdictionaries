#!/usr/bin/env ruby
require 'json'
require 'simstring'
require 'pp'

# Provide functionalities for text annotation.
# 
class TextAnnotator

  NOTERMWORDS = [ # terms will never include these words
    "is", "are", "am", "be", "was", "were", "do", "did",
    "doe", # does
    "what", "which", "when", "where", "who", "how",
    "a", "an", "the", "this", "that", "these", "those", "it", "its", "we", "our", "us", "they", "their", "them", "there", "then", "I", "he", "she", "my", "me", "his", "him", "her",
    "will", "shall", "may", "can", "cannot", "would", "should", "might", "could", "ought",
    "each", "every", "many", "much", "very",
    "more", "most", "than", "such", "several", "some", "both", "even",
    "and", "or", "but", "neither", "nor",
    "not", "never", "also", "much", "as", "well",
    "mani", # many
    "e.g"
  ]

  NOEDGEWORDS = [ # terms will never begin with these words, mostly prepositions
    "about", "above", "across", "after", "against", "along",
    "amid", "among", "around", "at", "before", "behind", "below",
    "beneath", "beside", "besides", "between", "beyond",
    "by", "concerning", "considering", "despite", "except",
    "excepting", "excluding",
    "for", "from", "in", "inside", "into", "like", 
    "of", "off", "on", "onto",
    "regarding", "since", 
    "through", "to", "toward", "towards",
    "under", "underneath", "unlike", "until", "upon",
    "versus", "via", "with", "within", "without",
    "dure" # during
  ]

  # Initialize the text annotator instance.
  #
  # * (array)  dictionaries  - The Id of dictionaries to be used for annotation.
  def initialize(dictionaries, tokens_len_max = 6, threshold = 0.85, rich=false)
    @dictionaries = dictionaries
    @dicids = @dictionaries.map{|d| d.id}
    @tokens_len_max = tokens_len_max
    @threshold = threshold
    @rich = rich

    @tokens_len_min ||= 1
    @tokens_len_max ||= 4
    @threshold ||= 0.85
    @rich ||= false

    @ssdbs = @dictionaries.inject({}) do |h, dic|
      h[dic.name] = Simstring::Reader.new(dic.ssdb_path)
      h[dic.name].measure = Simstring::Jaccard
      h[dic.name].threshold = @threshold
      h
    end
  end

  # Annotate an input text.
  #
  # * (string) text  - Input text.
  #
  def annotate(text)
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    tokens = Entry.tokenize(Entry.decapitalize(text))

    # index spans with their tokens and positions (array)
    span_index = {}
    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      next if NOTERMWORDS.include?(tokens[tbegin][:token])
      next if NOEDGEWORDS.include?(tokens[tbegin][:token])
      next unless Entry.es_search_prefix(tokens[tbegin][:token], @dicids).results.total > 0

      (1 .. @tokens_len_max).each do |tlen|
        break if tbegin + tlen > tokens.length
        break if (tokens[tbegin + tlen - 1][:position] - tokens[tbegin][:position]) + 1 > @tokens_len_max
        break if text[tokens[tbegin + tlen - 2][:start_offset] ... tokens[tbegin + tlen - 1][:end_offset]] =~ /[^A-Z]\.\s+[A-Z][a-z ]/ # sentence boundary
        break if NOTERMWORDS.include?(tokens[tbegin + tlen - 1][:token])
        next if NOEDGEWORDS.include?(tokens[tbegin + tlen - 1][:token])

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]

        position = {start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}

        if span_index.has_key?(span)
          span_index[span][:positions] << position
        else
          span_index[span] = {positions:[position]}
        end
      end
    end

    # To search mapping entries per span
    span_entries = {}
    bad_key = nil
    span_index.keys.each do |span|
      entries = Entry.es_search_term(span, @dicids, @threshold)

      if entries.present?
        span_entries[span] = entries
      end
    end

    # To collect annotated (anchored) spans per entry
    entry_anns = Hash.new([])
    span_entries.each do |span, entries|
      entries.each do |entry|
        entry_anns[entry[:id]] += span_index[span][:positions].collect{|p| {span:span, position:p, label:entry[:label], identifier:entry[:identifier], score:entry[:score]}}
      end
    end

    # To sort the spans. unnecessary at the moment, because already sorted.
    # sort{|a, b|
    #   span_index[a][:start_offset] == span_index[b][:start_offset] ?
    #   span_index[b][:end_offset] <=> span_index[a][:end_offset] :
    #   span_index[a][:start_offset] <=> span_index[b][:start_offset]    
    # }

    # To choose the best annotated span per entry
    entry_anns.each do |eid, anns|
      full_anns = anns
      best_anns = []
      full_anns.each do |ann|
        last_ann = best_anns.pop
        if last_ann.nil?
          best_anns.push(ann)
        elsif ann[:position][:start_offset] < last_ann[:position][:end_offset] #span_overlap?
          best_anns.push(ann[:score] > last_ann[:score] ? ann : last_ann) # prefer shorter span
        else
          best_anns.push(last_ann, ann)
        end
      end
      entry_anns[eid] = best_anns
    end

    # rewrite to denotations
    denotations = []
    entry_anns.each do |eid, anns|
      anns.each do |ann|
        d = {span:{begin:ann[:position][:start_offset], end:ann[:position][:end_offset]}, obj:ann[:identifier]}
        if @rich
          d[:score] = ann[:score]
          d[:label] = ann[:label]
        end
        denotations << d
      end
    end

    annotation = {
      text: text,
      denotations: denotations.uniq
    }
  end

  def annotate_ss(text)
    # tokens are produced in the order of their position.
    # tokens are normalzed, but stopwords are preserved.
    tokens = Entry.tokenize(Entry.decapitalize(text))

    # index spans with their tokens and positions (array)
    span_index = {}
    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      next if NOTERMWORDS.include?(tokens[tbegin][:token])
      next if NOEDGEWORDS.include?(tokens[tbegin][:token])

      (1 .. @tokens_len_max).each do |tlen|
        break if tbegin + tlen > tokens.length
        break if (tokens[tbegin + tlen - 1][:position] - tokens[tbegin][:position]) + 1 > @tokens_len_max
        break if text[tokens[tbegin + tlen - 2][:start_offset] ... tokens[tbegin + tlen - 1][:end_offset]] =~ /[^A-Z]\.\s+[A-Z][a-z ]/ # sentence boundary
        break if NOTERMWORDS.include?(tokens[tbegin + tlen - 1][:token])
        next if NOEDGEWORDS.include?(tokens[tbegin + tlen - 1][:token])

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]

        position = {start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}

        if span_index.has_key?(span)
          span_index[span][:positions] << position
        else
          span_index[span] = {positions:[position]}
        end
      end
    end

    # To search mapping entries per span
    span_entries = {}
    bad_key = nil
    span_index.keys.each do |span|
      entries = Entry.ss_search_term(span, @dictionaries, @ssdbs, @threshold)

      if entries.present?
        span_entries[span] = entries
      end
    end

    # To collect annotated (anchored) spans per entry
    entry_anns = Hash.new([])
    span_entries.each do |span, entries|
      entries.each do |entry|
        entry_anns[entry[:id]] += span_index[span][:positions].collect{|p| {span:span, position:p, label:entry[:label], identifier:entry[:identifier], score:entry[:score]}}
      end
    end

    # To sort the spans. unnecessary at the moment, because already sorted.
    # sort{|a, b|
    #   span_index[a][:start_offset] == span_index[b][:start_offset] ?
    #   span_index[b][:end_offset] <=> span_index[a][:end_offset] :
    #   span_index[a][:start_offset] <=> span_index[b][:start_offset]
    # }

    # To choose the best annotated span per entry
    entry_anns.each do |eid, anns|
      full_anns = anns
      best_anns = []
      full_anns.each do |ann|
        last_ann = best_anns.pop
        if last_ann.nil?
          best_anns.push(ann)
        elsif ann[:position][:start_offset] < last_ann[:position][:end_offset] #span_overlap?
          best_anns.push(ann[:score] > last_ann[:score] ? ann : last_ann) # prefer shorter span
        else
          best_anns.push(last_ann, ann)
        end
      end
      entry_anns[eid] = best_anns
    end

    # rewrite to denotations
    denotations = []
    entry_anns.each do |eid, anns|
      anns.each do |ann|
        d = {span:{begin:ann[:position][:start_offset], end:ann[:position][:end_offset]}, obj:ann[:identifier]}
        if @rich
          d[:score] = ann[:score]
          d[:label] = ann[:label]
        end
        denotations << d
      end
    end

    annotation = {
      text: text,
      denotations: denotations.uniq
    }
  end

end
