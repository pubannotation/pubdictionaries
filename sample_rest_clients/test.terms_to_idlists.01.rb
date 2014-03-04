#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get the list of labels for a list of IDs.
#
# * (string)  uri              - The URI of the sign in route.
#                                (e.g., http://localhost:3000/dictionaries)
# * (array)   dics             - The list of dictionary names for annotation.
# * (string)  email            - User's login ID.
# * (string)  password         - User's login password.
# * (hash)    annotation       - The hash including a list of labels.
# * (hash)    matching_options - The hash containig options for id search.
#
def get_idlists(uri, dics, email, password, annotation, matching_options)
  # 1. Initialize the options hash.
  options = {
    :headers => {
      :content_type => :json,
      :accept       => :json,
    },
    :user         => email,
    :password     => password, 
    :timeout      => 9999, 
    :open_timeout => 9999,
  }

  # 2. Create a rest client resource.
  resource = RestClient::Resource.new  "#{uri}/terms_to_idlists.json", options

  # 3. Retrieve the list of IDs.
  data = resource.post( 
    :dictionaries => dics.to_json,
    :annotation   => annotation.to_json,
    :options      => matching_options.to_json, 
    :content_type => :json,
    :accept       => :json,
  ) do |response, request, result|
    case response.code
    when 200
      JSON.parse(response.body)
    else
      $stdout.puts "Error code: #{response.code}"
      annotation
    end
  end

  return data
end



# Test code.
#
# * ARGV[0]  -  User's email.
# * ARGV[1]  -  User's password.
# * ARGV[2]  -  URI
# * ARGV[3-] -  Dictionaries
#
if __FILE__ == $0
  if ARGV.size < 4
    $stdout.puts "Usage:  #{$0}  Email  Password  URI  Dic1  Dic2  ..."
    exit
  end
  email            = ARGV[0]
  password         = ARGV[1]
  uri              = ARGV[2]
  dics             = ARGV[3, ARGV.length]
  annotation       = { "terms" => [ "NF-kappa B", "C-REL", "c-rel", "Brox", "may_be_not_exist"] }
  matching_options = { "threshold" => 0.3, "top_n" => 10 }

  result     = get_idlists(uri, dics, email, password, annotation, matching_options)

  $stdout.puts "Input:"
  $stdout.puts annotation["terms"].inspect
  
  $stdout.puts "Output:"
  if result.has_key? "error"
    $stdout.puts "   Error: #{result["error"]["message"]}"
  end
  if result.has_key? "idlists"
    $stdout.puts "   %-20s| %s" % ["TERM", "IDs"]
    annotation["terms"].each do |term|
      $stdout.puts "   %-10s| %s" % [term, result["idlists"][term].inspect]
    end
  end
  $stdout.puts 

end
