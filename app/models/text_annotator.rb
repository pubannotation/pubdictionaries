#!/usr/bin/env ruby
require 'json'

# Provide functionalities for text annotation.
# 
class TextAnnotator
  # Initialize the text annotator instance.
  #
  # * (array)  dictionaries  - The Id of dictionaries to be used for annotation.
  def initialize(dictionaries, tokens_len_min = 1, tokens_len_max = 6, threshold = 0.6)
    @dictionaries = dictionaries
    @tokens_len_min = tokens_len_min
    @tokens_len_max = tokens_len_max
    @threshold = threshold

    @tokens_len_min ||= 1
    @tokens_len_max ||= 6
    @threshold ||= 0.6
  end

  # Annotate an input text.
  #
  # * (string) text  - Input text.
  #
  def annotate(text)
    # tokens are produced in the order of their position
    tokens = tokenize(text)

    span_index = {}
    (0 ... tokens.length - @tokens_len_min + 1).each do |tbegin|
      (@tokens_len_min .. @tokens_len_max).each do |tlen|
        next if tbegin + tlen > tokens.length

        span = text[tokens[tbegin][:start_offset]...tokens[tbegin+tlen-1][:end_offset]]
        position = {start_offset: tokens[tbegin][:start_offset], end_offset: tokens[tbegin+tlen-1][:end_offset]}

        if span_index.has_key?(span)
          span_index[span][:positions] << position
        else
          span_index[span] = {positions:[position]}
        end
      end
    end

    mapping = Dictionary.find_ids(span_index.keys, @dictionaries, @threshold, true).delete_if{|k, v| v.empty?}
    {
      span_index: span_index,
      mapping: mapping
    }

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
        denotations << {span:{begin:a[:position][:start_offset], end:a[:position][:end_offset]}, obj:t}
      end
    end

    annotation = {
      text: text,
      denotations: denotations
    }
  end

  # Tokenize an input text using an analyzer of ElasticSearch.
  #
  # * (string) text  - Input text.
  #
  def tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/labels/_analyze?analyzer=standard_normalization', text), symbolize_names: true)[:tokens]
  end
end
