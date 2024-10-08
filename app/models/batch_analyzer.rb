class BatchAnalyzer
  INCREMENT_NUM_PER_TEXT = 100

  def initialize(dictionary)
    @dictionary = dictionary
    @uri = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @http = Net::HTTP::Persistent.new
    @post = Net::HTTP::Post.new(@uri.request_uri, 'Content-Type' => 'application/json')
  end

  def add_entries(entries)
    labels = entries.map(&:first)
    norm1list, norm2list = normalize(labels,
                                     @dictionary.normalizer1,
                                     @dictionary.normalizer2)
    @dictionary.add_entries(entries, norm1list, norm2list)
  end

  def shutdown
    @http.shutdown
  end

  private

  def normalize(texts, *normalizers)
    ## Explanation
    # This method returns the following results from input texts corresponding to normalizer.
    # texts:              ["abc def", "of", "ghi"]
    # normalize1 results: ["abcdef", "of", "ghi"]
    # normalize2 results: ["abcdef", "", "ghi"]

    raise ArgumentError, "Empty text in array" if texts.empty? || texts.any?{ _1.empty? }
    _texts = texts.map { _1.tr('{}', '()') }

    normalizers.map do |normalizer|
      body = { analyzer: normalizer, text: _texts }.to_json
      response = tokenize(body)

      tokens = JSON.parse(response.body, symbolize_names: true)[:tokens]

      # The 'tokens' variable is an array of tokenized words.
      # example: [{:token=>"abc", :start_offset=>0, :end_offset=>3, :type=>"<ALPHANUM>", :position=>0},
      #           {:token=>"def", :start_offset=>4, :end_offset=>7, :type=>"<ALPHANUM>", :position=>1},
      #           {:token=>"of", :start_offset=>8, :end_offset=>10, :type=>"<ALPHANUM>", :position=>102},
      #           {:token=>"ghi", :start_offset=>11, :end_offset=>14, :type=>"<ALPHANUM>", :position=>203}]


      # Large gaps in position values in tokens indicate text switching. It increases by 100.
      # To determine each text from results, grouping tokens as one text if difference of position value is within the gap.
      result = tokens.chunk_while { |a, b| b[:position] - a[:position] <= INCREMENT_NUM_PER_TEXT }
                     .reduce([[], 0]) do |(result, previous_position), words|
                       # If all words in the text are removed by stopwords, the difference in position value is more than 200.
                       # example: [{:token=>"abc", :start_offset=>0, :end_offset=>3, :type=>"<ALPHANUM>", :position=>0},
                       #           {:token=>"def", :start_offset=>4, :end_offset=>7, :type=>"<ALPHANUM>", :position=>1},
                       #           {:token=>"ghi", :start_offset=>11, :end_offset=>14, :type=>"<ALPHANUM>", :position=>203}]

                       # To obtain expected result, adding empty strings according to skipped texts number when difference of position value is over 200.
                       if (words.first[:position] - previous_position) > 200
                         skipped_texts_count = (words.first[:position] - previous_position) / INCREMENT_NUM_PER_TEXT - 1
                         skipped_texts_count.times { result << '' }
                       end

                       previous_position = words.last[:position]
                       result << words.map { _1[:token] }.join('')
                       [result, previous_position]
                     end.first

      # Skip judgment by position value cannot determine if the last texts were skipped.
      # If the last texts are skipped, add empty strings to avoid last result becomes nil.
      result << '' while result.size < texts.size

      result
    end
  end

  def tokenize(body)
    @post.body = body
    response = @http.request(@uri, @post)

    raise response.body unless response.kind_of? Net::HTTPSuccess
    response
  end
end
