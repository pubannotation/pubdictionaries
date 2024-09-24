class Analyzer
  INCREMENT_NUM_PER_TEXT = 100

  def initialize(use_persistent: false)
    @uri = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @http =
      if use_persistent
        Net::HTTP::Persistent.new
      else
        Net::HTTP.new(@uri.host, @uri.port)
      end
    @post = Net::HTTP::Post.new(@uri.request_uri, 'Content-Type' => 'application/json')
    @use_persistent = use_persistent
  end

  def normalize(text, normalizer)
    raise ArgumentError, "Empty text" if text.blank?
    _text = text.tr('{}', '()')
    body = { analyzer: normalizer, text: _text }.to_json
    response = tokenize(body)

    JSON.parse(response.body, symbolize_names: true)[:tokens].map{ _1[:token] }.join('')
  end

  def batch_normalize(texts, normalizer)
    ## Explanation
    # This method returns the following results from input texts corresponding to normalizer.
    # texts:              ["abc def", "of", "ghi"]
    # normalize1 results: ["abcdef", "of", "ghi"]
    # normalize2 results: ["abcdef", "", "ghi"]

    raise ArgumentError, "Empty text in array" if texts.empty? || texts.any?{ _1.empty? }
    _texts = texts.map { _1.tr('{}', '()') }
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
    tokens.chunk_while { |a, b| b[:position] - a[:position] <= INCREMENT_NUM_PER_TEXT }
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
  end

  def shutdown
    @http.shutdown
  end

  private

  def tokenize(body)
    @post.body = body
    response =
      if @use_persistent
        @http.request(@uri, @post)
      else
        @http.request(@post)
      end

    raise response.body unless response.kind_of? Net::HTTPSuccess
    response
  end
end
