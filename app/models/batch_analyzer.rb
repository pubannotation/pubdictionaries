class BatchAnalyzer
  INCREMENT_NUM_PER_TEXT = 100

  attr_reader :skipped_entries

  def initialize(dictionary)
    @dictionary = dictionary
    @uri = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @http = Net::HTTP::Persistent.new
    @post = Net::HTTP::Post.new(@uri.request_uri, 'Content-Type' => 'application/json')
    @skipped_entries = []
  end

  def add_entries(entries)
    labels = entries.map(&:first)
    norm1list, norm2list = normalize(labels,
                                     @dictionary.normalizer1,
                                     @dictionary.normalizer2)
    @dictionary.add_entries(entries, norm1list, norm2list)
  rescue => e
    # If batch normalization fails due to token limit, use binary search to find problematic entry
    if e.message.include?('max_token_count') || e.message.include?('illegal_state_exception')
      Rails.logger.warn "[BatchAnalyzer] Batch of #{entries.size} entries failed token limit, using binary search"
      add_entries_with_binary_search(entries)
    else
      raise
    end
  end

  # Use binary search to efficiently find and skip entries that exceed Elasticsearch token limit
  def add_entries_with_binary_search(entries, depth = 0)
    return if entries.empty?

    # Try processing the batch
    begin
      labels = entries.map(&:first)
      norm1list, norm2list = normalize(labels, @dictionary.normalizer1, @dictionary.normalizer2)
      @dictionary.add_entries(entries, norm1list, norm2list)
    rescue => e
      if e.message.include?('max_token_count') || e.message.include?('illegal_state_exception')
        # If only one entry, it's the problematic one - skip it and log
        if entries.size == 1
          label, identifier, _ = entries.first
          @skipped_entries << { label: label, identifier: identifier, reason: 'token_limit' }
          Rails.logger.warn "[BatchAnalyzer] Skipped entry (token limit): '#{label}' (#{identifier})"
          return
        end

        # Split in half and process recursively
        mid = entries.size / 2
        left_half = entries[0...mid]
        right_half = entries[mid..-1]

        Rails.logger.debug "[BatchAnalyzer] Splitting batch (#{entries.size} -> #{left_half.size} + #{right_half.size}) at depth #{depth}"

        add_entries_with_binary_search(left_half, depth + 1)
        add_entries_with_binary_search(right_half, depth + 1)
      else
        raise
      end
    end
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
