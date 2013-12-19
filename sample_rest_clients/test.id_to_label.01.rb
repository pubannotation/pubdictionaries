#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get the list of labels for a list of IDs.
#
# * (string)  uri           - The URI of the sign in route. This URI involves the base dictionary name.
# * (string)  email         - User's login ID.
# * (string)  password      - User's login password.
# * (hash)    annotation    - The hash including a list of labels.
# * (hash)    options       - The hash containig options for id search.
#
def get_label_list(uri, email, password, annotation, options)
	# Prepare the connection to the web service.
	resource = RestClient::Resource.new( 
		"#{uri}/text_annotations.json",
		:timeout      => 300, 
		:open_timeout => 300,
		)

	# Retrieve the list of labels.
	data = resource.post( 
		:user         => {email:email, password:password},
		:annotation   => annotation.to_json,
		:options      => options.to_json, 
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



# Text code.
#
# * ARGV[0]  -  User's email.
# * ARGV[1]  -  User's password.
# * ARGV[2]  -  URI
#
if __FILE__ == $0
	if ARGV.size != 3
		$stdout.puts "Usage:  #{$0}  <email>  <password>  <uri>"
		exit
	end
	email      = ARGV[0]
	password   = ARGV[1]
	uri        = ARGV[2]


	# Prepare data and option objects
	annotation = { "ids" => [ "1", "3", "5", "4790", "new_id", "new_id_2"] }
	options    = { "task" => "id_to_label" }

	result     = get_label_list(uri, email, password, annotation, options)

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
