module StringManipulator
  
  # Tokenize an input.
  #   @text   - a string of input text
  #   @return - a hash of tokens based on their indices.
  #
  def tokenize( text )
    tokens = {}

    # Tokenizes an input text
    tmp = text.split(/\s|(\W|_)/).reject { |t| t.empty? }   # does not match unicode, check \p{word}
  
    # Finds the index of each token
    abs_pos = 0
    tmp.each_with_index do |t, idx|
      cur_pos = text.index( t, abs_pos )
      tokens[idx] = {token: t, begin: cur_pos, end: cur_pos + t.length}
      abs_pos = cur_pos + t.length 
    end

    tokens
  end

  # Normalize a string based on string normalization options.
  #
  def normalize_str(str, norm_opts)
    # Tokenizes an input string
    tokens = tokenize(str)
    
    # Normalizes the string
    norm_str = ""
    (0...tokens.size).each do |idx|
      norm_token = String.new(tokens[idx][:token])

      # 1. Performs stemming 
      if norm_opts[:stemmed] != 0
        norm_token = norm_token.stem
      end

      # 2. Downcase the string
      if norm_opts[:lowercased] != 0
        norm_token = norm_token.downcase
      end

      # 3. Replace every hyphen with a space
      if norm_opts[:hyphen_replaced] != 0
        norm_token = norm_token.gsub("-", " ")
      end

      norm_str += norm_token
      if (idx+1) < tokens.size and tokens[idx][:end] < tokens[idx+1][:begin]
        norm_str += str[tokens[idx][:end]...tokens[idx+1][:begin]]
      end
    end

    norm_str
  end

end
