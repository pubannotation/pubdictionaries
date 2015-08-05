module ExpressionsHelper
  def expressions_uris_to_json(arguments = {})
    hash = Hash.new
    hash[arguments[:terms]] = []
    arguments[:expressions_uris].each do |expression_uri|
      if arguments[:output] == 'id'
        hash[arguments[:terms]] << expression_uri.uri.resource
      else
        hash[arguments[:terms]] << {
          id: expression_uri.uri.resource,
          expression: expression_uri.expression.words,
          dictionary: "http://pubdictionaries.org#{dictionary_path(expression_uri.dictionary.title)}",
          dictionary_name: expression_uri.dictionary.title
        }
      end
    end
    return hash.to_json
  end

  def rest_api_search_expression_url
    # search_key_params = %w(terms dictionaries)
    # p params.keys.select{|key| search_key_params.include?(key)}
    rest_api_params_hash = {terms: params[:terms], output: params[:output], format: 'json'}
    rest_api_params_hash[:format] = params[:format] if params[:format]
    rest_api_params = rest_api_params_hash.to_param
    if params[:dictionaries]
      dictionaries = Array.new
      params[:dictionaries].each do |dictionary_title|
        dictionaries << "dictionaries[]=#{dictionary_title}"
      end
      rest_api_params += "&#{dictionaries.join('&')}"
    end
    "http://pubdictionaries.org#{search_expressions_path}?terms=#{params[:terms]}&format=json"
    "http://pubdictionaries.org#{search_expressions_path}?#{rest_api_params}"
  end

  def search_order_link(order_key)
    if order_key == params[:order_key]
      case params[:order]
      when 'ASC'
        order = 'DESC'
      else
        order = 'ASC'
      end
      link_to order_key.capitalize, "#{request.original_url}&order_key=#{order_key}&order=#{order}", class: order.downcase
    else
      link_to order_key.capitalize, "#{request.original_url}&order_key=#{order_key}&order=ASC", class: 'asc'
    end
  end
end
