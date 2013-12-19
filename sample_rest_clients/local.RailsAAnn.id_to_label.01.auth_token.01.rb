#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get the authentication token from the PubDictionaries by signing in.
#  * (string)  uri       - The URI of the sign in route.
#  * (string)  email     - The login email .
#  * (string)  password  - The password for the email.
#
def get_auth_token(uri, email, password)
	# Sign into the PubDictionaries.
	res = RestClient.post( 
		uri,
		:user         => {:email=>email, :password=>password},
		:content_type => :json,
		:accept       => :json,
		)

	# Retrieve the authentication token.
	auth_token = JSON.parse(res)["auth_token"]
	
	return auth_token
end

# Get the list of labels for a list of IDs.
#  * (string)  uri           - The URI of the sign in route. This URI involves the base dictionary name.
#  * (string)  auth_token    - The authentication token that identifies the user's session in the server.
#                              The user dictionary corresponding to the base dictionary will be identified
#                              by this session information.
#  * (hash)    annotation    - The hash including a list of labels.
#  * (hash)    options       - The hash containig options for id search.
#
def get_label_list(uri, auth_token, annotation, options)
	# Prepare the connection to the web service.
	resource = RestClient::Resource.new( 
		"#{uri}/text_annotations.json?auth_token=#{auth_token}",
		:timeout => 300, 
		:open_timeout => 300,
		)

	# Retrieve the list of labels.
	json_result = resource.post( 
		:annotation   => annotation.to_json,
		:options      => options.to_json, 
		:content_type => :json,
		:accept       => :json,
		)

	result = JSON.parse(json_result)

	return result
end

# Destroy auth_token.
#  * (string)  uri           - The URI of the sign in route.
#  * (string)  auth_token    - The authentication token that identifies the user's session to be destroyed.
#
def destroy_auth_token(uri, auth_token)
	result = RestClient.delete( 
		uri,
		:params       => {:auth_token => auth_token},
		:content_type => :json,
		:accept       => :json,
		)
	return result
end



# Test code.
if __FILE__ == $0
	#user_email     = ARGV[0]
	#user_password  = ARGV[1]

	user_email     = "priancho@gmail.com"
	user_password  = "password"

	# 1. Get the authentication token by signing in.
	auth_token = get_auth_token("localhost:3000/users/sign_in.json", user_email, user_password)

	$stderr.puts "Authentication token: #{auth_token}"
	$stderr.puts


	# Prepare data and option objects
	annotation = { "ids" => [ "1", "3", "5", "4790", "new_id", "new_id_2"] }
	options    = { "task" => "id_to_label" }
	uri        = "localhost:3000/dictionaries/EntrezGene%20-%20Homo%20Sapiens"

	result     = get_label_list(uri, auth_token, annotation, options)

	$stderr.puts " %-20s| %-20s" % ["ID", "LABEL"]
	annotation["ids"].each do |id|
		$stderr.puts " %-20s| %-20s" % [id, result["denotations"][id]]
	end
	$stderr.puts 

	# 3. Destroy the authentication token.
	result = destroy_auth_token("localhost:3000/users/sign_out.json", auth_token)

	$stderr.puts "Delete the authentication token: #{result.code} (Code 200 is means success)."
	$stderr.puts
end
