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

end
