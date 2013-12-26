require 'stemmify'



class ApplicationController < ActionController::Base
  protect_from_forgery
  after_filter :store_location

  def store_location
    # store last url - this is needed for post-login redirect to whatever the user last visited.
    if (request.fullpath != "/users/sign_in" &&
      request.fullpath != "/users/sign_up" &&
      request.fullpath != "/users/password" &&
      !request.xhr?) # don't store ajax calls

      if request.format == "text/html" || request.content_type == "text/html"
        session[:previous_url] = request.fullpath
        session[:last_request_time] = Time.now.utc.to_i
      end
    end
  end

  def after_sign_in_path_for(resource)
    valid_time_span = 120     # 120 seconds

    if Time.now.utc.to_i - session[:last_request_time] < valid_time_span
      return session[:previous_url] || root_path
    else
      return root_path
    end
  end
  
  # Returns true if the creator of a dictionary is same to the current_user (devise gem)
  def is_current_user_same_to_creator?(dictionary)
    if dictionary.creator == current_user.email
      return true
    else 
      return false
    end
  end

  # Normalizes a string based on string normalization options
  #    Ref - text_to_trie.rb in AutomaticAnnotator
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

  # Returns a hash of tokens with indices
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

    return tokens
  end
  
end
