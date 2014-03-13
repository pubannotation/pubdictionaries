require 'set'


require File.join( Rails.root, '..', 'simstring/swig/ruby/simstring')
require File.join( File.dirname( __FILE__ ), 'text_annotator/text_annotator' )


class DictionariesController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_filter :authenticate_user!, except: [ 
    :index, :show, 
    :text_annotation_with_single_dic_readme, :text_annotation_with_single_dic, 
    :text_annotation_with_multiple_dic_readme, :select_dictionaries_for_text_annotation, :text_annotation_with_multiple_dic, 
    :id_mapping_with_multiple_dic_readme, :select_dictionaries_for_id_mapping, :id_mapping,
    :label_mapping_with_multiple_dic_readme, :select_dictionaries_for_label_mapping, :label_mapping,
  ]

  # Disable CSRF check for REST-API actions.
  skip_before_filter :verify_authenticity_token, :only => [
    :text_annotation_with_multiple_dic, :text_annotation_with_single_dic, :id_mapping, :label_mapping
  ], :if => Proc.new { |c| c.request.format == 'application/json' }


  ###########################
  #####     ACTIONS     #####
  ###########################

  def index
    dic_type = params[:dictionary_type]

    base_dics, order, order_direction = Dictionary.get_showables  current_user, dic_type
    @grid_dictionaries = get_dictionaries_grid_view  base_dics, order, order_direction, 30

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: base_dics }
    end
  end

  # Show the content of an original dictionary and its corresponding user dictionary.
  def show
    @base_dic  = Dictionary.find_showable_by_title  params[:id], current_user
    
    if not user_signed_in? or @base_dic.user_dictionaries.nil? 
      @user_dic = nil
    else
      @user_dic = @base_dic.user_dictionaries.find_by_user_id(current_user.id)
    end

    if @base_dic
      # Replace the page title with the dictionary name
      @page_title = @base_dic.title

      if ["ori", "del", "new", "ori_del", "ori_del_new"].include?  params[:query]
        @export_entries = build_export_entries  params[:query]
      else
        @g1, @g2, @g3   = get_entries_grid_views
      end
    end

    respond_to do |format|
      format.html {
        if @base_dic.nil?
          redirect_to dictionaries_url
        end
        # Otherwise, render the default view template.
      }
      format.tsv { 
        send_data tsv_data(@export_entries), 
        filename: "#{@base_dic.title}.#{params[:query]}.tsv", 
        type:     "text/tsv" 
      }
    end
  end

  # Disable (or enable) multiple selected entries (from the base dictionary).
  def disable_entries
    dic = Dictionary.find_showable_by_title  params[:id], current_user

    if dic
      user_dic = UserDictionary.get_or_create_user_dictionary  dic, current_user

      if params["commit"] == "Disable selected entries" and 
         params.has_key? :basedic_remained_entries and 
         params[:basedic_remained_entries].has_key? :selected

        # Register selected entries as disabled.
        params[:basedic_remained_entries][:selected].each do |eid|
          if not user_dic.removed_entries.exists?  entry_id: eid
            user_dic.removed_entries.create  entry_id: eid
          end
        end
      end
   
      if params["commit"] == "Enable selected entries" and
         params.has_key? :basedic_disabled_entries and
         params[:basedic_disabled_entries].has_key? :selected

        params[:basedic_disabled_entries][:selected].each do |eid|
          if user_dic.removed_entries.exists?  entry_id: eid
            user_dic.removed_entries.find_by_entry_id(eid).destroy
          end
        end
      end
    end

    respond_to do |format|
      format.html { redirect_to :back }
    end
  end

  # Remove multiple selected entries (from the user dictionary).
  def remove_entries
    dic = Dictionary.find_showable_by_title  params[:id], current_user

    if dic
      user_dic = UserDictionary.get_or_create_user_dictionary  dic, current_user

      if not params[:userdic_new_entries][:selected].nil?
        params[:userdic_new_entries][:selected].each do |id|
          entry = user_dic.new_entries.find  id
          if not entry.nil?
            entry.destroy
          end
        end
      end
    end

    respond_to do |format|
      format.html { redirect_to :back }
    end
  end

  def new
    @dictionary = Dictionary.new
    @dictionary.creator = current_user.email     # set the creator with the user name (email)

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @dictionary }
    end
  end

  def create
    # Creates a dictionary
    @dictionary = User.find(current_user.id).dictionaries.new  params[:dictionary]
    @dictionary.title.strip!
    @dictionary.creator = current_user.email
    b_basedic_saved = @dictionary.save

    # Fills the entries of the dictionary
    b_entries_saved = false
    if b_basedic_saved
      b_entries_saved = fill_dic  params[:dictionary]
    end

    respond_to do |format|
      if b_basedic_saved and b_entries_saved
        create_simstring_db
        format.html{ redirect_to @dictionary, notice: 'Dictionary was successfully created.' }
      elsif b_basedic_saved and not b_entries_saved
        @dictionary.destroy
        format.html{ redirect_to :back, notice: 'Failed to save a dictionary!' }
      else
        format.html{ render action: 'new' }
      end
    end
  end


  # Destroy a base dictionary and the associated user dictionaries (of other users too).
  def destroy
    base_dic = Dictionary.find_showable_by_title  params[:id], current_user

    if not base_dic  
      ret_url = :back
      ret_msg = "Cannot find a dictionary."

    else
      # if not is_destroyable?(base_dic)
      flag, msg = base_dic.is_destroyable?  current_user
      if flag == false
        ret_url = :back
        ret_msg = msg

      else
        # Delete the entries of the base dictionary (@dictionary.destroy is too slow).
        Entry.where("dictionary_id = ?", base_dic.id).delete_all

        # Delete new and removed entries of the associated user dictionaries.
        base_dic.user_dictionaries.all.each do |user_dic|
          NewEntry.where("user_dictionary_id = ?", user_dic.id).delete_all
          RemovedEntry.where("user_dictionary_id = ?", user_dic.id).delete_all
        end

        # Delete the associated user dictionaries.
        UserDictionary.where("dictionary_id = ?", base_dic.id).delete_all

        # Delete the dictionary.
        Dictionary.where("id = ?", base_dic.id).delete_all

        # Delete the associated SimString DB.
        delete_simstring_db  base_dic.title

        ret_url = dictionaries_url
        ret_msg = msg
      end
    end

    respond_to do |format|
      format.html{ redirect_to ret_url, notice: ret_msg }
      format.json { head :no_content }
    end
  end


  # Multiple dictionary annotator URL generator.
  def text_annotation_with_multiple_dic_readme
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate URL"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "matching_method" => params["annotation_strategy"], 
        "min_tokens"      => params["min_tokens"],
        "max_tokens"      => params["max_tokens"],
        "threshold"       => params["threshold"],
        "top_n"           => params["top_n"],
        }

      @annotator_uri = "http://#{request.host}:#{request.port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  # Select dictionaries for text_annotation_with_multiple_dic_readme.
  def select_dictionaries_for_text_annotation
    base_dics, order, order_direction = Dictionary.get_showables  current_user
    @grid_dictionaries = get_dictionaries_grid_view  base_dics

    respond_to do |format|
      format.html { render layout: false }
    end
  end

  # Annotate a given text using base dictionaries (and corresponding user dictionaries).
  def text_annotation_with_multiple_dic
    basedic_names = JSON.parse(params["dictionaries"])
    text          = params["text"]
    opts          = get_opts_from_params(params)

    # Annotate input text by using dictionaries.
    results = []
    basedic_names.each do |basedic_name|
      base_dic = Dictionary.find_showable_by_title  basedic_name, current_user
      if not base_dic.nil?
        results += annotate_text_with_dic(text, basedic_name, opts, current_user)
      end
    end

    # Return the results.
    respond_to do |format|
      format.json { render :json => results }
    end
  end

  # Single dictionary annotator URL generator.
  def text_annotation_with_single_dic_readme
    @annotator_uri = ""
    basedic_name   = params[:id]
    base_dic       = Dictionary.find_showable_by_title  basedic_name, current_user
    
    if base_dic.nil?
      ret_msg = "Cannot find the dictionary."

    else
      if params[:commit] == "Generate URL"
        request_params = { 
          "matching_method" => params["annotation_strategy"], 
          "min_tokens"      => params["min_tokens"],
          "max_tokens"      => params["max_tokens"],
          "threshold"       => params["threshold"],
          "top_n"           => params["top_n"],
          }

        @annotator_uri = "http://#{request.host}:#{request.port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
      end
    end

    respond_to do |format|
      format.html { 
        if base_dic.nil?
          redirect_to dictionaries_path, :message => ret_msg
        end
      }      
    end
  end

  # Text annotation API as a member rote.
  def text_annotation_with_single_dic
    basedic_name  = params[:id]
    text          = params["text"]
    opts          = get_opts_from_params(params)

    # Annotate input text by using a dictionary.
    results = []  
    base_dic = Dictionary.find_showable_by_title  basedic_name, current_user
    if not base_dic.nil?
      results = annotate_text_with_dic(text, basedic_name, opts, current_user)
    end

    # Return the results.
    respond_to do |format|
      format.json { render :json => results }
    end
  end


  # Multiple dictionary ID mapper URL generator.
  def id_mapping_with_multiple_dic_readme
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate URL"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "threshold"       => params["threshold"],
        "top_n"           => params["top_n"],
        "output_format"   => params["output_format"],
        }

      @annotator_uri = "http://#{request.host}:#{request.port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  # Select dictionaries for id_mapping_with_multiple_dic_readme.
  def select_dictionaries_for_id_mapping
    base_dics, order, order_direction = Dictionary.get_showables  current_user
    @grid_dictionaries = get_dictionaries_grid_view  base_dics

    respond_to do |format|
      format.html { render layout: false }
    end
  end

  # For a given list of terms, find the list of IDs for each of them.
  #
  # * Input  : [term_1, term_2, ... ,term_n]
  # * Output : {"term_1"=>[{"uri"=>111, "dictionary_name"=>"EntrezGene"}, {... }, ...], ...}
  #
  def id_mapping
    dic_titles = JSON.parse(params["dictionaries"])
    terms      = params["terms"].nil? ? nil : JSON.parse(params["terms"])
    opts       = get_opts_from_params(params)
    results    = {}

    # 1. Get a list of entries for each term.
    dic_titles.each do |dic_title|
      if Dictionary.find_showable_by_title(dic_title, current_user).nil?
        next
      end

      annotator = TextAnnotator.new  dic_title, current_user
      if not annotator.dictionary_exist?  dic_title
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

    # 2. Sort the results based on the similarity values.
    results.each_pair do |term, entries|   
      entries.sort! { |x,y| y[:sim] <=> x[:sim] }
    end

    # 3. Keep top-n results.
    results.each_pair do |term, entries|   
      if opts["top_n"] < 0 and entries.size >= opts["top_n"]
        results[term] = entries[0...opts["top_n"]]
      end
    end

    # 4. Format the output. 
    results.each_pair do |term, entries|
      if opts["output_format"] == nil or opts["output_format"] == "simple"
        results[term].collect! do |entry| 
          entry[:uri]
        end
      else
        results[term].collect! do |entry| 
          { uri: entry[:uri], score: entry[:sim], dictionary_name: entry[:dictionary_name] }
        end
      end
    end

    # Return the results.
    respond_to do |format|
      format.json { render :json => results }
    end
  end

  # Multiple dictionary label mapper URL generator.
  def label_mapping_with_multiple_dic_readme
    @annotator_uri = ""

    if params[:commit] == "Add selected dictionaries"
      params[:dictionaries] = get_selected_diclist(params)

    elsif params[:commit] == "Generate URL"
      request_params = { 
        "dictionaries"    => params["dictionaries"],
        "top_n"           => params["top_n"],
        "output_format"   => params["output_format"],
        }

      @annotator_uri = "http://#{request.host}:#{request.port}#{request.fullpath.split("?")[0]}?#{request_params.to_query}"
    end

    respond_to do |format|
      format.html 
    end
  end

  # Select dictionaries for id_mapping_with_multiple_dic_readme.
  def select_dictionaries_for_label_mapping
    base_dics, order, order_direction = Dictionary.get_showables  current_user
    @grid_dictionaries = get_dictionaries_grid_view  base_dics

    respond_to do |format|
      format.html { render layout: false }
    end
  end

  # Return a list of labels for a given list of IDs.
  def label_mapping
    dic_titles = JSON.parse(params["dictionaries"])
    ids        = params["ids"].nil?   ? nil : JSON.parse(params["ids"])
    opts       = get_opts_from_params(params)
    results    = {}
    
    dic_titles.each do |dic_title|
      dic = Dictionary.find_showable_by_title  dic_title, current_user

      if not dic.nil?
        annotator  = TextAnnotator.new  dic_title, current_user

        if annotator.dictionary_exist?  dic_title
          ids_to_labels = annotator.ids_to_labels  ids, opts

          ids_to_labels.each_pair do |id, labels|
            # Remove duplicate labels for the same ID.
            labels.uniq!
            
            # Format the output value.
            if nil == opts["output_format"] or "simple" == opts["output_format"]
              new_value = labels
            else  # opts["output_format"] == "rich"
              new_value = labels.collect do |label|
                {label: label, dictionary_name: dic_title}
              end
            end

            # Store the result.
            if results.key?  id
              results[id] += new_value
            else
              results[id] = new_value
            end
          end
        end
      end
    end

    # Return the result.
    respond_to do |format|
      format.json { render :json => results }
    end
  end


  ###########################
  #####     METHODS     #####
  ###########################
  private

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

  # Create grid views for remained, disabled, and new entries.
  def get_entries_grid_views()
    ids = @user_dic.nil? ? [] : @user_dic.removed_entries.get_disabled_entry_idlist

    # 1. Remained base entries.
    remained_entries = @base_dic.entries.empty? ? Entry.none : @base_dic.entries.get_remained_entries(ids)
    grid_basedic_remained_entries = initialize_grid(remained_entries, 
      :name => "basedic_remained_entries",
      :order => "view_title",        # Initial ordering column.
      :order_direction => "asc",     # Initial ordering direction.
      :per_page => 30, )

    # 2. Disabled base entries.
    disabled_entries = @base_dic.entries.empty? ? Entry.none : @base_dic.entries.get_disabled_entries(ids)
    grid_basedic_disabled_entries = initialize_grid(disabled_entries,
      :name => "basedic_disabled_entries",
      :order => "view_title",
      :order_direction => "asc",
      :per_page => 30, )

    # 3. New entries.
    if @user_dic.nil?
      new_entries = NewEntry.none
    else
      new_entries = @user_dic.new_entries.empty? ? NewEntry.none : @user_dic.new_entries.get_new_entries
    end
    grid_userdic_new_entries = initialize_grid(new_entries, 
      :name => "userdic_new_entries",
      :order => "view_title",
      :order_direction => "asc",
      :per_page => 30, )
    
    return grid_basedic_remained_entries, grid_basedic_disabled_entries, grid_userdic_new_entries
  end

  # Create a list of entries for export.
  def build_export_entries(export_type)
    export_entries = [ ]

    if export_type == "ori"
      # Export: all entries of an original dictionary.
      export_entries = @base_dic.entries.select("view_title, label, uri")

    elsif export_type == "del"
      # Export: all deleted entries from an original dictionary.
      if not @user_dic.nil?
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dic.id).pluck(:entry_id).uniq
        export_entries = @base_dic.entries.select("view_title, label, uri").find(removed_entry_ids)
      end    

    elsif export_type == "new"
      # Export: all new entries.
      if not @user_dic.nil?
        export_entries = @user_dic.new_entries.select("view_title, label, uri")
      end

    elsif export_type == "ori_del"
      # Export: entries of an original dictionary that are not deleted by a user.
      if @user_dic.nil?
        export_entries = @base_dic.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dic.id).pluck(:entry_id).uniq
        export_entries = @base_dic.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri")
      end

    elsif export_type == "ori_del_new"
      # Export: a list of active entries of an original and user dictionaries.
      if @user_dic.nil?
        export_entries = @base_dic.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dic.id).pluck(:entry_id).uniq
        new_entries       = @user_dic.new_entries  

        export_entries = @base_dic.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri") + new_entries
      end
    end

    export_entries
  end

  # Convert a collection of entries in tsv format
  def tsv_data(entries)
    entries.collect{ |e| "#{e.view_title}\t#{e.label}\t#{e.uri}\n" }.join
  end

  # Fill entries for a given dictionary
  def fill_dic(dic_params)
    input_file  = dic_params[:file]
    sep         = dic_params[:separator]
    norm_opts   = { lowercased:      dic_params[:lowercased], 
                    hyphen_replaced: dic_params[:hyphen_replaced],
                    stemmed:         dic_params[:stemmed],
                  }
    str_error   = ""

    if not input_file
      str_error = "File is not selected" 
    else
      # Add entries to the dictionary
      data = input_file.read
      data.gsub! /\r\n?/, "\n"     # replace \r, \r\n with \n

      entries = []
      data.split("\n").each do |line|
        line.chomp!
        items = line.split(sep)

        # Model#new creates an object but not save it, while Model#create do both.
        entries << @dictionary.entries.new( { view_title:  items[0], 
                                             search_title: normalize_str(items[0], norm_opts), 
                                             uri:          items[1],
                                             label:        items[2],     # nil if label column is not given.
                                          } )
        if entries.length == 2000
          @dictionary.entries.import entries
          entries.clear
        end
      end

      # Uses activerecord-import gem to accelerate the bulk import speed
      # @dictionary.entries.import entries
      if entries.length != 0
        @dictionary.entries.import entries
      end
    end

    return str_error
  end

  # Create a simstring db
  def create_simstring_db
    dbfile_path = Rails.root.join('public/simstring_dbs', params[:dictionary][:title]).to_s

    #time_start = Time.new
    #logger.debug "... Starts to generate a simstring DB."

    db = Simstring::Writer.new(dbfile_path, 3, true, true)     # (filename, n-gram, begin/end marker, unicode)

    # @dictionary.entries.each do |entry|     #     This is too slow
    Entry.where(dictionary_id: @dictionary.id).pluck(:search_title).uniq.each do |search_title|
      db.insert(search_title)
    end

    db.close
    #logger.debug "... Finishes generating a simstring DB."
    #logger.debug "...... Total time elapsed: #{Time.new - time_start} seconds"
  end

  # Delete a simstring db and associated files
  def delete_simstring_db( filename )
    dbfile_path = Rails.root.join('public/simstring_dbs', filename).to_s
    
    # Remove the main db file
    begin
      File.delete(dbfile_path)
    rescue
      # Silently ignore the error
    end

    # Remove auxiliary db files
    pattern = dbfile_path + ".[0-9]+.cdb"
    Dir.glob(dbfile_path + '.*.cdb').each do |aux_file|
      if /#{pattern}/.match(aux_file) 
        begin
          File.delete(aux_file)
        rescue
          # Silently ignores the error
        end
      end
    end
  end

  # Annotate input text by using a given dictionary.
  def annotate_text_with_dic(text, basedic_name, opts, current_user)
    annotator  = TextAnnotator.new  basedic_name, current_user
    results    = []

    if annotator.dictionary_exist?  basedic_name
      tmp_result = annotator.annotate  text, opts
      tmp_result.each do |entry|
        entry["dictionary_name"] = basedic_name
      end
      results += tmp_result
    end

    results
  end

  # Retrieve option values from the GET params.
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
    
  # Get a list of selected dictionaries.
  def get_selected_diclist(params)
    diclist = JSON.parse(params[:dictionaries])

    if params.has_key? :dictionaries_list and params[:dictionaries_list].has_key? :selected
      params[:dictionaries_list][:selected].each do |dic_id|
        dic = Dictionary.find_by_id  dic_id
        if not dic.nil? and not diclist.include?  dic.title
          diclist << dic.title
        end
      end
    end

    diclist.to_json
  end
end



