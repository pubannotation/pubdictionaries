#!/usr/bin/env ruby

################################################################
#
#   By using this script, you can annotate input text with
# multiple dictionaries. You can also select one of two matching 
# algorithms, exact and approximate.
#
#   To get the URL of specific dictionaries and annotation options, 
# please click the sub-menus of the "Dictionaries" menu at the left 
# menu-bar and click the "Get Annotator URL" button at the bottom 
# of the page.
#
################################################################


require 'json'
require 'rest_client'


# Annotate the text by using the selected dictionaries and the associated user dictionaries.
#
# * (string)  url       - The URL of an annotator. It involves dictionary names and annotation options.
#                           (e.g., http://pubdictionaries.dbcls.jp:80/dictionaries/text_annotation?dictionaries=%5B%22EntrezGene+-+Homo+Sapiens%22%2C%22EntrezGene+-+Mus+musculus%22%5D&matching_method=approximate&max_tokens=6&min_tokens=1&threshold=0.6&top_n=0)
# * (string)  email     - User's login ID.
# * (string)  password  - User's login password.
# * (hash)    text      - Input text.
#
def annotate_text(url, email, password, text)
  # 1. Initialize the REST-API option hash.
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
  resource = RestClient::Resource.new("#{url}", options)

  # 3. Run the annotation.
  data = resource.post(:text => text) do |response, request, result|
    case response.code
    when 200
      JSON.parse(response.body)
    else
      $stdout.puts "Error code: #{response.code}"
    end
  end
  
  return data
end


# Test code.
#
# * ARGV[0]   -  User's email.
# * ARGV[1]   -  User's password.
# * ARGV[2]   -  Annotator URL.
# 
if __FILE__ == $0  
  if ARGV.size != 3
    $stdout.puts "Usage:  #{$0}  Email  Password  URI"
    exit
  end

  # Prepare data.
    email        = ARGV[0]     # Use an empty string "" to use the API as a guest user.
    password     = ARGV[1]     # Use an empty string "" to use the API as a guest user.
    url          = ARGV[2]
    sample_text  = "Negative regulation of human immunodeficiency virus type 1 expression in monocytes: role of the 65-kDa plus 50-kDa NF-kappa B dimer.\nAlthough monocytic cells can provide a reservoir for viral production in vivo, their regulation of human immunodeficiency virus type 1 (HIV-1) transcription can be either latent, restricted, or productive. These differences in gene expression have not been molecularly defined. In THP-1 cells with restricted HIV expression, there is an absence of DNA-protein binding complex formation with the HIV-1 promoter-enhancer associated with markedly less viral RNA production. This absence of binding was localized to the NF-kappa B region of the HIV-1 enhancer; the 65-kDa plus 50-kDa NF-kappa B heterodimer was preferentially lost. Adding purified NF-kappa B protein to nuclear extracts from cells with restricted expression overcomes this lack of binding. In addition, treatment of these nuclear extracts with sodium deoxycholate restored their ability to form the heterodimer, suggesting the presence of an inhibitor of NF-kappa B activity. Furthermore, treatment of nuclear extracts from these cells that had restricted expression with lipopolysaccharide increased viral production and NF-kappa B activity. Antiserum specific for NF-kappa B binding proteins, but not c-rel-specific antiserum, disrupted heterodimer complex formation. Thus, both NF-kappa B-binding complexes are needed for optimal viral transcription. Binding of the 65-kDa plus 50-kDa heterodimer to the HIV-1 enhancer can be negatively regulated in monocytes, providing one mechanism restricting HIV-1 gene expression."
  
  # Annotate the text.
  result = annotate_text(url, email, password, sample_text)
  
  # Show the result.
  $stdout.puts "Input:"
  $stdout.puts sample_text
  $stdout.puts

  result.each do |entry|
    $stdout.puts "   #{entry.inspect} - matched string: \"#{sample_text[entry["begin"]...entry["end"]]}\""
  end
  
end

