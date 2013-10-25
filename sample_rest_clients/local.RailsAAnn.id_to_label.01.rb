#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Prepare data and option objects
ids = [ "1", "3", "5" ]
json_annotation = JSON.generate( { 
	"ids"      => ids,
} )
json_options = JSON.generate( {
	"task" => "id_to_label", 
	})

# Prepare connection to a web service
dictionary_name = "EntrezGene - Homo Sapiens"
rest_api        = URI.escape("localhost:3000/dictionaries/#{dictionary_name}/text_annotations/")

resource = RestClient::Resource.new( 
	rest_api,
	:timeout => 300, 
	:open_timeout => 300 )

# Send the request and get the results
response = resource.post( :annotation   => json_annotation,
                          :options      => json_options, 
                          :content_type => :json,
                          :accept       => :json )

# Output the results
puts "Input: #{ids.inspect}" 
puts 

puts response.code
puts

puts JSON.parse(response)["denotations"].inspect
puts 


