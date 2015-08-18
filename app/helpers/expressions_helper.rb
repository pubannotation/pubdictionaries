module ExpressionsHelper
  def expressions_uris_to_json(arguments = {})
    hash = Hash.new
    hash[arguments[:terms]] = []
    if arguments[:expressions_uris].present?
      arguments[:expressions_uris].each do |expression_uri|
        if arguments[:output] == 'id'
          hash[arguments[:terms]] << expression_uri.uri.resource if hash[arguments[:terms]].include?(expression_uri.uri.resource) == false && expression_uri.uri.resource.present?
        else
          hash[arguments[:terms]] << {
            id: expression_uri.uri.resource,
            expression: expression_uri.expression.words,
            dictionary: "http://pubdictionaries.org#{dictionary_path(expression_uri.dictionary.title)}",
            dictionary_name: expression_uri.dictionary.title
          }
        end
      end
    end
    return hash.to_json
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
