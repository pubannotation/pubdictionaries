#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Prepare data and option objects
ids = [ "1", "3", "5" ]
json_data = JSON.generate( { 
	"ids"      => ids,
} )

json_options = JSON.generate( { 
	"dictionary_name" => "EntrezGene - Homo Sapiens",
} )


# Prepare connection to a web service
server  = "pubdictionaries.dbcls.jp"
service = "rest_api/ids_to_labels/"

resource = RestClient::Resource.new( 
	"#{server}/#{service}",
	:timeout => 300, 
	:open_timeout => 300 )

# Send the request and get the results
response = resource.post( :data         => json_data,
                          :options      => json_options, 
                          :content_type => :json,
                          :accept       => :json )

# Output the results
puts "Input: #{ids.inspect}" 
puts 

puts response.code
puts

puts JSON.parse(response)["labels"].inspect
puts 


