#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get the list of labels for a list of IDs.
#
# * (string)  uri           - The URI of the sign in route.
#                             (e.g., http://localhost:3000/dictionaries)
# * (array)   dics          - The list of dictionary names for annotation.
# * (string)  email         - User's login ID.
# * (string)  password      - User's login password.
# * (hash)    annotation    - The hash including a list of labels.
#
def get_label_list(uri, dics, email, password, annotation)
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
  resource = RestClient::Resource.new  "#{uri}/ids_to_labels.json", options

  # 3. Retrieve the list of labels.
  data = resource.post( 
    :dictionaries => dics.to_json, 
    :annotation   => annotation.to_json, 
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
  email      = ARGV[0]
  password   = ARGV[1]
  uri        = ARGV[2]
  dics       = ARGV[3, ARGV.length]
  annotation = { "ids" => [ "1", "3", "5", "100008564", "100009600", "new_id", "new_id_2"] }

  result     = get_label_list(uri, dics, email, password, annotation)

  $stdout.puts "Input:"
  $stdout.puts annotation["ids"].inspect
  
  $stdout.puts "Output:"
  if result.has_key? "error"
    $stdout.puts "   Error: #{result["error"]["message"]}"
  end
  if result.has_key? "denotations"
    $stdout.puts "   %-20s| %-20s" % ["ID", "LABEL"]
    annotation["ids"].each do |id|
      $stdout.puts "   %-20s| %-20s" % [id, result["denotations"][id]]
    end
  end
  $stdout.puts 

end


