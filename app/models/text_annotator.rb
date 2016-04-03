#!/usr/bin/env ruby
require 'json'

# Provide functionalities for text annotation.
# 
class TextAnnotator
  # Initialize the text annotator instance.
  #
  # * (array)  dictionaries  - The Id of dictionaries to be used for annotation.
  def initialize(dictionaries, tokens_len_min = 1, tokens_len_max = 6, threshold = 0.7)
    @dictionaries = dictionaries
    @tokens_len_min = tokens_len_min
    @tokens_len_max = tokens_len_max
    @threshold = threshold
  end

  # Annotate an input text.
  #
  # * (string) text  - Input text.
  #
  def annotate(text)
    es_annotation(text)
  end

  def es_annotation(text)
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
    # annotated_spans = mapping.keys.inject([]){|c, s| c += span_index[s][:positions].map{|p| {span:s, position:p, tags:mapping[s]}}}

    # To filter sub-optimal tags
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

    # tags = mapping.keys.inject({}){|h, k| mapping[k]  }

    # cache = {}
    # prev = {position: {start_offset:0, :end_offset:0}}
    # annotated_spans.each do |s|
    #   cache.clear
    # end

    # sort{|a, b|
    #   span_index[a][:start_offset] == span_index[b][:start_offset] ?
    #   span_index[b][:end_offset] <=> span_index[a][:end_offset] :
    #   span_index[a][:start_offset] <=> span_index[b][:start_offset]    
    # }

    # annotated.collect{|s| {span: s, start_offset:span_index[s][:start_offset], end_offset:span_index[s][:end_offset], }}

    # span_index.each_key do |span|
    #   span_index[span][:es_annotation] = Label.search_as_term(span, @dictionaries)
    # end
    # span_index
  end

  def tokenize(text)
    raise ArgumentError, "Empty text" if text.empty?
    (JSON.parse RestClient.post('http://localhost:9200/labels/_analyze?analyzer=standard_normalization', text), symbolize_names: true)[:tokens]
  end

  # Reformat the results.
  def format_results(results)
    results_array = results.collect do |item|
      {
        span: {begin: item[:offset].begin, end: item[:offset].end},
        obj: item[:uri],
      }
    end

    results_array.uniq
  end
end