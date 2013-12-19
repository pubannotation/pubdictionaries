#!/usr/bin/env ruby

require 'json'
require 'rest_client'


# Get the authentication token from the PubDictionaries by signing in.
#  * (string)  uri       - The URI of the sign in route.
#  * (string)  email     - The login email .
#  * (string)  password  - The password for the email.
#
def get_auth_token(uri, email, password)
	# Sign into the PubDictionaries (Don't raise exceptions).
	RestClient.post( 
		uri,
		:user         => {:email=>email, :password=>password},
		:content_type => :json,
		:accept       => :json,
	) { | response, request, result, &block |
		result = JSON.parse(response)

		case response.code
		when 200
			return result["auth_token"]
		else
			$stderr.puts "Error: #{result["message"]}"
			return nil
		end
	}
end

# Annotate the text by using the base dictionary and the associated user dictionary, which 
# will be identified by the auth_token.
#  * (string)  uri           - The URI of the sign in route. This URI involves the base dictionary name.
#  * (string)  auth_token    - The authentication token that identifies the user's session in the server.
#                              The user dictionary corresponding to the base dictionary will be identified
#                              by this session information.
#  * (hash)    annotation    - The hash including text for annotation.
#  * (hash)    options       - The hash containig various options for annotation.
#
def annotate_text(uri, auth_token, annotation, options)
	# Prepare the connection to the text annotation service.
	resource = RestClient::Resource.new( 
		"#{uri}/text_annotations.json?auth_token=#{auth_token}",
		:timeout      => 300, 
		:open_timeout => 300,
		)

	# Annotate the text
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
#
# * ARGV[0] - User's email as the first command-line argument.
# * ARGV[1] - User's password as the second command-line argument.
#
if __FILE__ == $0
	user_email     = ARGV[0]
	user_password  = ARGV[1]

	if user_email.nil? or user_password.nil?
		$stderr.puts "Usage: #{$0} <user email> <password>"
		exit
	end

	# 1. Get the authentication token by signing in.
	auth_token = get_auth_token("http://pubdictionaries.dbcls.jp/users/sign_in.json", user_email, user_password)
	if auth_token
		$stderr.puts "Authentication token: #{auth_token}"
		$stderr.puts
	else
		$stderr.puts "Authentication failed."
		exit
	end

	# 2. Annotate the text.
	annotation = { "text"=>"Negative regulation of human immunodeficiency virus type 1 expression in monocytes: role of the 65-kDa plus 50-kDa NF-kappa B dimer.\nAlthough monocytic cells can provide a reservoir for viral production in vivo, their regulation of human immunodeficiency virus type 1 (HIV-1) transcription can be either latent, restricted, or productive. These differences in gene expression have not been molecularly defined. In THP-1 cells with restricted HIV expression, there is an absence of DNA-protein binding complex formation with the HIV-1 promoter-enhancer associated with markedly less viral RNA production. This absence of binding was localized to the NF-kappa B region of the HIV-1 enhancer; the 65-kDa plus 50-kDa NF-kappa B heterodimer was preferentially lost. Adding purified NF-kappa B protein to nuclear extracts from cells with restricted expression overcomes this lack of binding. In addition, treatment of these nuclear extracts with sodium deoxycholate restored their ability to form the heterodimer, suggesting the presence of an inhibitor of NF-kappa B activity. Furthermore, treatment of nuclear extracts from these cells that had restricted expression with lipopolysaccharide increased viral production and NF-kappa B activity. Antiserum specific for NF-kappa B binding proteins, but not c-rel-specific antiserum, disrupted heterodimer complex formation. Thus, both NF-kappa B-binding complexes are needed for optimal viral transcription. Binding of the 65-kDa plus 50-kDa heterodimer to the HIV-1 enhancer can be negatively regulated in monocytes, providing one mechanism restricting HIV-1 gene expression."}
	options    = {
		"task"            => "annotation",     # Specify the task.
		"matching_method" => "exact",          # Text annotation strategy (exact string matching).
		"min_tokens"      => 2,                # Minimum number of tokens for annotation. 
		"max_tokens"      => 8,                # Maximum number of tokens for annotation.
		}
	uri        = "http://pubdictionaries.dbcls.jp/dictionaries/EntrezGene%20-%20Homo%20Sapiens"

	result = annotate_text(uri, auth_token, annotation, options)

	$stderr.puts "Input text:"
	$stderr.puts result["text"].inspect
	$stderr.puts "Annotation:"
	result["denotations"].each do |entry|
		$stderr.puts "   #{entry.inspect} - matched string in the text: \"#{annotation["text"][entry["begin"]...entry["end"]]}\""
	end
	$stderr.puts


	# 3. Destroy the authentication token.
	result = destroy_auth_token("http://pubdictionaries.dbcls.jp/users/sign_out.json", auth_token)

	$stderr.puts "Delete the authentication token: #{result.code} (Code 200 is means success)."
	$stderr.puts
end

