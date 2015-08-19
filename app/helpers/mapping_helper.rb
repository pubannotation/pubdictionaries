module MappingHelper

  def get_opts_from_params(params)
    opts = {}
    opts["min_tokens"]      = params["min_tokens"].to_i
    opts["max_tokens"]      = params["max_tokens"].to_i
    opts["matching_method"] = params["matching_method"]
    opts["threshold"]       = params["threshold"].to_f
    opts["top_n"]           = params["top_n"].to_i
    opts["output_format"]   = params["output_format"]

    return opts
  end

  # Create grid views for dictionaries
  def get_dictionaries_grid_view(base_dics, order = 'created_at', order_direction = 'desc', per_page = 10000)
    grid_dictionaries_view = initialize_grid(base_dics,
      :name => "dictionaries_list",
      :order => order,
      :order_direction => order_direction,
      :per_page => per_page, )
    # if params[:dictionaries_list] && params[:dictionaries_list][:selected]
    #   @selected = params[:dictionaries_list][:selected]
    # end
  
    return grid_dictionaries_view
  end

  # Get a list of selected dictionaries.
  def get_selected_diclist(params)
    diclist = params[:dictionaries].split(',')

    if params.has_key? :dictionaries_list and params[:dictionaries_list].has_key? :selected
      params[:dictionaries_list][:selected].each do |dic_id|
        dic = Dictionary.find_by_id  dic_id
        if not dic.nil? and not diclist.include?  dic.title
          diclist << dic.title
        end
      end
    end

    diclist.join(',')
  end

  def annotate_text_with_dic(text, basedic_name, opts, current_user)
    annotator = TextAnnotator.new basedic_name, current_user
    results   = []

    if annotator.dictionary_exist? basedic_name
      tmp_result = annotator.annotate text, opts
      tmp_result.each do |entry|
        entry["dictionary"] = basedic_name
      end
      results += tmp_result
    end

    results
  end

  def rest_api_search_expression_url(text_for)
    rest_api_params_hash = {terms: params[:terms], output: params[:output], format: 'json'}
    rest_api_params_hash[:format] = params[:format] if params[:format]
    rest_api_params_hash[:fuzziness] = params[:fuzziness] if params[:fuzziness]
    rest_api_params = rest_api_params_hash.to_param
    if params[:dictionaries]
      dictionaries = Array.new
      params[:dictionaries].each do |dictionary_title|
        dictionaries << "dictionaries[]=#{dictionary_title}"
      end
      rest_api_params += "&#{dictionaries.join('&')}"
    end
    case text_for
    when 'curl'
      "curl -d '#{rest_api_params}' http://#{request.host_with_port}#{url_for(controller: 'mapping', action: params[:action])}"
    when 'href'
      "http://#{request.host_with_port}#{url_for(controller: 'mapping', action: params[:action])}?#{rest_api_params}"
    end
  end
end
