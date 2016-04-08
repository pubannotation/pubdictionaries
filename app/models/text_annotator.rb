#!/usr/bin/env ruby
require 'json'
require 'pp'

# Provide functionalities for text annotation.
# 
class TextAnnotator
  # Initialize the text annotator instance.
  #
  # * (array)  dictionaries  - The Id of dictionaries to be used for annotation.
  def initialize(dictionaries, tokens_len_min = 1, tokens_len_max = 6, threshold = 0.8, rich=false)
    @dictionaries = dictionaries
    @tokens_len_min = tokens_len_min
    @tokens_len_max = tokens_len_max
    @threshold = threshold
    @rich = rich

    @tokens_len_min ||= 1
    @tokens_len_max ||= 6
    @threshold ||= 0.8
    @rich ||= false
  end

  # Annotate an input text.
  #
  # * (string) text  - Input text.
  #
  def annotate(text)
    # tokens are produced in the order of their position
    tokens = Label.tokenize(text)

    span_index = {}
    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        break if tbegin + tlen > tokens.length
        break if (tokens[tbegin + tlen - 1][:position] - tokens[tbegin][:position]) > @tokens_len_max - 1

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]

        position = {start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}

        if span_index.has_key?(span)
          span_index[span][:positions] << position
        else
          span_index[span] = {positions:[position]}
        end
      end
    end

    mapping = {}
    bad_key = nil
    span_index.keys.each do |k|
      unless bad_key.nil?
        next if k.start_with?(bad_key)
        bad_key = nil
      end
      r = Dictionary.find_label_ids(k, @dictionaries, @threshold, true)
      if r[:es_results] > 0
        mapping[k] = r[:ids]
      else
        bad_key = k
      end
    end

    # mapping = Dictionary.find_ids(span_index.keys, @dictionaries, @threshold, true).delete_if{|k, v| v.empty?}

    # To collect spans per tag
    tags = {}
    mapping.each do |s, ts|
      ts.each do |t|
        if tags.has_key? t[:identifier]
          tags[t[:identifier]][:anns] += span_index[s][:positions].collect{|p| {span:s, position:p, score:t[:score]}}
        else
          tags[t[:identifier]] = {
            label: t[:label],
            anns: span_index[s][:positions].collect{|p| {span:s, position:p, score:t[:score]}}
          }
        end
      end
    end

    # sort{|a, b|
    #   span_index[a][:start_offset] == span_index[b][:start_offset] ?
    #   span_index[b][:end_offset] <=> span_index[a][:end_offset] :
    #   span_index[a][:start_offset] <=> span_index[b][:start_offset]    
    # }

    # To choose the best span per tag
    tags.each do |t, v|
      full_anns = v[:anns]
      best_anns = []
      full_anns.each do |ann|
        last_ann = best_anns.pop
        if last_ann.nil?
          best_anns.push(ann)
        elsif ann[:position][:start_offset] < last_ann[:position][:end_offset] #span_overlap?
          best_anns.push(ann[:score] > last_ann[:score] ? ann : last_ann)
        else
          best_anns.push(last_ann, ann)
        end
      end
      v[:anns] = best_anns
    end    

    # tags_to_annotation
    denotations = []
    tags.each do |t, v|
      v[:anns].each do |a|
        d = {span:{begin:a[:position][:start_offset], end:a[:position][:end_offset]}, obj:t}
        d[:score] = a[:score] if @rich
        denotations << d
      end
    end

    annotation = {
      text: text,
      denotations: denotations
    }
  end
end
