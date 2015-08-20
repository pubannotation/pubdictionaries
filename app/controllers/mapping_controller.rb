class MappingController < ApplicationController
	include MappingHelper
	include ExpressionsHelper

  # Disable CSRF check for REST-API actions.
  skip_before_filter :verify_authenticity_token, :only => [
    :term_to_id_post
  ], :if => Proc.new { |c| c.request.format == 'application/json' }

  def search 
    @dictionaries, order, order_direction = Dictionary.get_showables( current_user, nil)
    @dictionaries_include_resuls = []
    if params[:terms].present?
      if params[:dictionaries].present?
        # when filtered by dictionaries
        @search_target_dictionaries = Dictionary.where(['title IN (?)', params[:dictionaries]])
        if @search_target_dictionaries.present?
          dictionary_ids = @search_target_dictionaries.collect{|dictionary| dictionary.id }
          expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.dictionaries(dictionary_ids).includes(:uris)
        end
      else
        # when not filtered by dictionaries
        expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.includes(:uris)
        @search_target_dictionaries = expressions.collect{|d| d.dictionaries }.flatten.uniq
      end

      if expressions
        per_page = 30
        expression_ids = expressions.collect{|expression| expression.id }.uniq
        if dictionary_ids.present?
          expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).where('dictionary_id IN (?)', dictionary_ids).page(params[:page])
        else
          expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).page(params[:page])
        end
        # detect order
        if params[:order_key] == 'expression'
          order = "expressions.words #{params[:order]}"
        elsif params[:order_key] == 'id'
          order = "uris.resource #{params[:order]}"
        elsif params[:order_key] == 'dictionary'
          order = "dictionaries.title #{params[:order]}"
        else
          order = ActiveRecord::Base.send(:sanitize_sql_array, ["position(expression_id::text in '#{ expression_ids.join(',')}')"])
        end
        @expressions_uris = expressions_uris.order(order).per(per_page)
      end
      @dictionaries_include_resuls = expressions_uris.collect{|eu| eu.dictionary}.uniq if expressions_uris.present?
      @dictionaries = @dictionaries - @search_target_dictionaries if @search_target_dictionaries.present?
    end

    respond_to do |format|
      format.html
      format.json { 
        render json: expressions_uris_to_json({expressions_uris: expressions_uris.order(order), terms: params[:terms], output: params[:output]}) 
      }
    end
  end

  def expression_to_id
    @dictionaries, order, order_direction = Dictionary.get_showables( current_user, nil)
    @dictionaries_include_resuls = []
    if params[:dictionaries].present?
      # when filtered by dictionaries
      @search_target_dictionaries = Dictionary.where(['title IN (?)', params[:dictionaries]])
      if @search_target_dictionaries.present?
        dictionary_ids = @search_target_dictionaries.collect{|dictionary| dictionary.id }
        expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.dictionaries(dictionary_ids).includes(:uris)
      end
    else
      # when not filtered by dictionaries
      if params[:terms].present?
        expressions = Expression.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.includes(:uris)
        @search_target_dictionaries = expressions.collect{|d| d.dictionaries }.flatten.uniq if expressions.present?
      end
    end
    @dictionaries = @dictionaries - @search_target_dictionaries if @search_target_dictionaries.present?

    if expressions
      per_page = 30
      expression_ids = expressions.collect{|expression| expression.id }.uniq
      if dictionary_ids.present?
        expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).where('dictionary_id IN (?)', dictionary_ids).page(params[:page])
      else
        expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['expression_id IN (?)', expression_ids]).page(params[:page])
      end
      # detect order
      if params[:order_key] == 'expression'
        order = "expressions.words #{params[:order]}"
      elsif params[:order_key] == 'id'
        order = "uris.resource #{params[:order]}"
      elsif params[:order_key] == 'dictionary'
        order = "dictionaries.title #{params[:order]}"
      else
        order = ActiveRecord::Base.send(:sanitize_sql_array, ["position(expression_id::text in '#{ expression_ids.join(',')}')"])
      end
      @dictionaries_include_resuls = expressions_uris.collect{|eu| eu.dictionary}.uniq if expressions_uris.present?
      @expressions_uris = expressions_uris.order(order).per(per_page)
    end

    respond_to do |format|
      format.html
      format.json { 
        expression_uris = expressions_uris.order(order) if expressions_uris.present?
        render json: expressions_uris_to_json({expressions_uris: expression_uris, terms: params[:terms], output: params[:output]}) 
      }
    end
  end

  def id_to_expression
    @dictionaries, order, order_direction = Dictionary.get_showables( current_user, nil)
    @dictionaries_include_resuls = []
    if params[:dictionaries].present?
      # when filtered by dictionaries
      @search_target_dictionaries = Dictionary.where(['title IN (?)', params[:dictionaries]])
      if @search_target_dictionaries.present?
        dictionary_ids = @search_target_dictionaries.collect{|dictionary| dictionary.id }
        uris = Uri.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.dictionaries(dictionary_ids).includes(:expressions)
      end
    else
      # when not filtered by dictionaries
      if params[:terms].present?
        uris = Uri.search_fuzzy({query: params[:terms], fuzziness: params[:fuzziness]}).records.includes(:expressions)
        @search_target_dictionaries = uris.collect{|d| d.dictionaries }.flatten.uniq if uris.present?
      end
    end
    @dictionaries = @dictionaries - @search_target_dictionaries if @search_target_dictionaries.present?

    if uris.present?
      per_page = 30
      uri_ids = uris.collect{|uri| uri.id }.uniq
      if dictionary_ids.present?
        expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['uri_id IN (?)', uri_ids]).where('dictionary_id IN (?)', dictionary_ids).page(params[:page])
      else
        expressions_uris = ExpressionsUri.includes([:expression, :uri, :dictionary]).where(['uri_id IN (?)', uri_ids]).page(params[:page])
      end
      # detect order
      if params[:order_key] == 'expression'
        order = "expressions.words #{params[:order]}"
      elsif params[:order_key] == 'id'
        order = "uris.resource #{params[:order]}"
      elsif params[:order_key] == 'dictionary'
        order = "dictionaries.title #{params[:order]}"
      else
        order = ActiveRecord::Base.send(:sanitize_sql_array, ["position(uri_id::text in '#{ uri_ids.join(',')}')"])
      end
      @dictionaries_include_resuls = expressions_uris.collect{|eu| eu.dictionary}.uniq if expressions_uris.present?
      @expressions_uris = expressions_uris.order(order).per(per_page)
    end

    respond_to do |format|
      format.html
      format.json { 
        expression_uris = expressions_uris.order(order) if expressions_uris.present?
        render json: expressions_uris_to_json({expressions_uris: expression_uris, terms: params[:terms], output: params[:output]}) 
      }
    end
  end

  def term_to_id
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "threshold"       => params["threshold"],
        "top_n"           => params["top_n"],
        "output_format"   => params["output_format"],
        }

      @annotator_uri = "http://#{request.host_with_port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  def term_to_id_post
    params["terms"] = params["_json"] if params["_json"].present? && params["_json"].class == Array
    params["terms"] = params["terms"].split(/[\t\r\n]+/) if params["terms"].present? && params["terms"].class == String
    params["dictionaries"] = params["dictionaries"].split(/[\t\r\n,]+/) if params["dictionaries"].present? && params["dictionaries"].class == String

    terms      = params["terms"]
    dic_titles = params["dictionaries"]
    opts       = get_opts_from_params(params)
    results    = {}

    if terms.present?
      # 1. Get a list of entries for each term.
      dic_titles.each do |dic_title|
        if Dictionary.find_showable_by_title(dic_title, current_user).nil?
          next
        end

        annotator = TextAnnotator.new dic_title, current_user
        if not annotator.dictionary_exist? dic_title
          next
        end

        # Retrieve an entry list for each term.
        terms_to_entrylists = annotator.terms_to_entrylists  terms, opts
        
        # Add add "dictionary_name" value to each entry object and store
        #   all of them into results.
        terms_to_entrylists.each_pair do |term, entries|
          entries.each do |entry| 
            entry[:dictionary_name] = dic_title
          end
          
          results[term].nil? ? results[term] = entries : results[term] += entries
        end
      end

      # 2. Perform post-processes.
      results.each_pair do |term, entries|   
        # 2.1. Sort the results based on the similarity values.
        entries.sort! { |x, y| y[:sim] <=> x[:sim] }

        # 2.2. Remove duplicate entries of the same ID.
        results[term] = entries.uniq { |elem| elem[:uri] }     # Assume it removes the later element.

        # 2.3. Keep top-n results.
        if opts["top_n"] < 0 and entries.size >= opts["top_n"]
          results[term] = entries[0...opts["top_n"]]
        end

        # 2.4. Format the output.
        if opts["output_format"] == nil or opts["output_format"] == "simple"
          results[term].collect! do |entry| 
            entry[:uri]
          end
        else
          results[term].collect! do |entry| 
            { id: entry[:uri], score: entry[:sim], dictionary: entry[:dictionary_name] }
          end
        end
      end
    end

    # 3. Return the results.
    respond_to do |format|
      format.json { render :json => results }
    end
  end

  def id_to_label
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "output_format"   => params["output_format"],
        }

      @annotator_uri = "http://#{request.host_with_port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  def id_to_label_post
    params["ids"] = params["_json"] if params["_json"].present? && params["_json"].class == Array
    params["ids"] = params["ids"].split(/[\t\r\n]+/) if params["ids"].present? && params["ids"].class == String
    params["dictionaries"] = params["dictionaries"].split(/[\t\r\n,]+/) if params["dictionaries"].present? && params["dictionaries"].class == String
    ids        = params["ids"]
    dic_titles = params["dictionaries"]
    opts = {}
    opts["output_format"] = params["output_format"]
    results    = {}
    
    dics = dic_titles.map{|t| Dictionary.find_showable_by_title t, current_user}.compact
    if dics.present? && ids.present?
      ids.each do |id|
        results[id] = []
        dics.each do |dic|
          entry = Entry.where(uri: id, dictionary_id: dic).first
          if entry.present?
            results[id] << if opts["output_format"] == "rich"
              {label: entry.view_title, dictionary: dic.title}
            else
              entry.view_title
            end
          end
        end
        results[id].uniq!
      end
    end

    # Return the result.
    respond_to do |format|
      format.json { render :json => results }
    end
  end

  def text_annotation
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "matching_method" => params["annotation_strategy"], 
        "min_tokens"      => params["min_tokens"],
        "max_tokens"      => params["max_tokens"],
        "threshold"       => params["threshold"],
        "top_n"           => params["top_n"],
        }

      @annotator_uri = "http://#{request.host_with_port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  def text_annotation_post
    params["dictionaries"] = params["dictionaries"].split(/[\t\r\n,]+/) if params["dictionaries"].present? && params["dictionaries"].class == String

    text          = params["text"]
    basedic_names = params["dictionaries"]
    opts          = get_opts_from_params(params)

    # Annotate input text by using dictionaries.
    results = []
    if text.present?
      basedic_names.each do |basedic_name|
        base_dic = Dictionary.find_showable_by_title  basedic_name, current_user
        unless base_dic.nil?
          results += annotate_text_with_dic(text, basedic_name, opts, current_user)
        end
      end
    end

    # Return the results.
    respond_to do |format|
      format.json { render :json => results }
    end
  end

  def select_dictionaries
    @from = params[:from]

    base_dics, order, order_direction = Dictionary.get_showables current_user
    @grid_dictionaries = get_dictionaries_grid_view  base_dics

    respond_to do |format|
      format.html { render layout: false }
    end
  end

end
