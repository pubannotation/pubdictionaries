require 'set'


require File.join( Rails.root, '..', 'simstring-1.0/swig/ruby/simstring')
require File.join( File.dirname( __FILE__ ), 'text_annotations/text_annotator' )


class DictionariesController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_filter :authenticate_user!, 
    except: [:index, :show, :text_annotation_with_multiple_dic, :text_annotation_with_single_dic,
      :ids_to_labels, :terms_to_idlists]

  # Disable CSRF check for specific actions.
  skip_before_filter :verify_authenticity_token, 
    :only => [:annotate_text, :ids_to_labels, :terms_to_idlists], 
    :if => Proc.new { |c| c.request.format == 'application/json' }


  ###########################
  #####     ACTIONS     #####
  ###########################

  def index
    # @dictionaries = Dictionary.all
    @dictionaries = Dictionary.get_showable_dictionaries(current_user).all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @dictionaries }
    end
  end

  # Show the content of an original dictionary and its corresponding user dictionary.
  def show
    @dictionary = Dictionary.find_by_title(params[:id])
    @page_title = @dictionary.title     # Replace the page title with the dictionary name

    @user_dictionary = user_signed_in? ? @dictionary.user_dictionaries.find_by_user_id(current_user.id) : nil

    if ["ori", "del", "new", "ori_del", "ori_del_new"].include? params[:query]
      @export_entries = build_export_entries(params[:query])
    else
      @grid_basedic_remained_entries, @grid_basedic_disabled_entries, @grid_userdic_new_entries = get_grid_views()
    end

    respond_to do |format|
      format.html # show.html.erb
      format.tsv { send_data tsv_data(@export_entries), 
        filename: "#{@dictionary.title}.#{params[:query]}.tsv", 
        type:     "text/tsv" }
    end
  end

  # Disable (or enable) multiple selected entries (from the base dictionary).
  def disable_entries
    dic      = Dictionary.find_by_title(params[:id])
    user_dic = UserDictionary.get_or_create_user_dictionary(dic, current_user)

    if params["commit"] == "Disable selected entries" and 
       params.has_key? :basedic_remained_entries and 
       params[:basedic_remained_entries].has_key? :selected

      # Register selected entries as disabled.
      params[:basedic_remained_entries][:selected].each do |eid|
        if not user_dic.removed_entries.exists?(entry_id: eid)
          user_dic.removed_entries.create(entry_id: eid)
        end
      end
    end
 
    if params["commit"] == "Enable selected entries" and
       params.has_key? :basedic_disabled_entries and
       params[:basedic_disabled_entries].has_key? :selected

      params[:basedic_disabled_entries][:selected].each do |eid|
        if user_dic.removed_entries.exists?(entry_id: eid)
          user_dic.removed_entries.find_by_entry_id(eid).destroy
        end
      end
    end

    respond_to do |format|
      format.html { redirect_to :back }
    end
  end

  # Remove multiple selected entries (from the user dictionary).
  def remove_entries
    dictionary       = Dictionary.find_by_title(params[:id])
    user_dictionary  = UserDictionary.find_or_create(dictionary, current_user)

    if not params[:userdic_new_entries][:selected].nil?
      params[:userdic_new_entries][:selected].each do |id|
        entry = user_dictionary.new_entries.find(id)
        if not entry.nil?
          entry.destroy
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
    @dictionary         = User.find(current_user.id).dictionaries.new( params[:dictionary] )
    @dictionary.creator = current_user.email
    b_basedic_saved = @dictionary.save

    # Fills the entries of the dictionary
    b_entries_saved = false
    if b_basedic_saved
      b_entries_saved = fill_dic(params[:dictionary])
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
    base_dic = Dictionary.find_by_title(params[:id])
    
    # if not is_destroyable?(base_dic)
    if not base_dic.is_destroyable?(current_user)
      ret_url = :back
      ret_msg = "This dictionary can be deleted only by its creator."
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
      delete_simstring_db(base_dic.title)

      ret_url = dictionaries_url
      ret_msg = "The dictionary is successfully deleted."
    end

    respond_to do |format|
      format.html{ redirect_to ret_url, notice: ret_msg }
      format.json { head :no_content }
    end
  end


  # Annotate a given text using base dictionaries (and corresponding user dictionaries).
  def text_annotation_with_multiple_dic
    basedic_names, ann, opts = get_data_params1(params)
    user_id = User.get_user_id(params["user"])

    results = []
    if user_id == :invalid
      ann["error"] = {"message" => "Invalid email or password"}
    else
      basedic_names.each do |basedic_name|
        annotator  = TextAnnotator.new(basedic_name, user_id)   # user_id is nil if it is guest
        if annotator.dictionary_exist?(basedic_name) == true
          tmp_result = annotator.annotate(ann, opts)
          tmp_result.each do |entry|
            entry["dictionary_name"] = basedic_name
          end
          results += tmp_result
        end
      end
    end
    ann["denotations"] = results

    # Return the results.
    respond_to do |format|
      format.json { render :json => ann }
    end
  end

  # Text annotation API as a member rote.
  def text_annotation_with_single_dic
    basedic_name, ann, opts = get_data_params2(params)
    user_id = User.get_user_id(params["user"])

    results = []
    if user_id == :invalid
      ann["error"] = {"message" => "Invalid email or password"}
    else
      annotator  = TextAnnotator.new(basedic_name, user_id)   # user_id is nil if it is guest
      if annotator.dictionary_exist?(basedic_name) == true
        tmp_result = annotator.annotate(ann, opts)
        tmp_result.each do |entry|
          entry["dictionary_name"] = basedic_name
        end
        results += tmp_result
      end
    end
    ann["denotations"] = results

    # Return the results.
    respond_to do |format|
      format.json { render :json => ann }
    end
  end

  # Return a list of labels for a given list of IDs.
  def ids_to_labels
    basedic_names, ann, opts = get_data_params1(params)
    user_id = User.get_user_id(params["user"])

    results = {}
    if user_id == :invalid
      ann["error"] = {"message" => "Invalid email or password"}
    else
      basedic_names.each do |basedic_name|
        annotator  = TextAnnotator.new(basedic_name, user_id)
        if annotator.dictionary_exist?(basedic_name) == true
          tmp_result = annotator.ids_to_labels(ann, opts)
          tmp_result.each_value do |id_labels|
            id_labels.each do |label|
              label["dictionary_name"] = basedic_name
            end
          end
          tmp_result.each_pair do |id, labels|
            if results.key?(id)
              results[id] += labels
            else
              results[id] = labels
            end
          end
        end
      end
    end
    ann["denotations"] = results

    # Return the result.
    respond_to do |format|
      format.json { render :json => ann }
    end
  end

  # For a given list of terms, find the list of IDs for each of them.
  #
  # * Input  : [term_1, term_2, ... ,term_n]
  # * Output : {"term_1"=>[ID_1, ID_24, ID432], "term_2"=>[ ... ], ... }
  #
  def terms_to_idlists
    basedic_names, ann, opts = get_data_params1(params)
    user_id = User.get_user_id(params["user"])

    results = {}
    if user_id == :invalid
      ann["error"] = {"message" => "Invalid email or password"}
    else
      basedic_names.each do |basedic_name|
        annotator  = TextAnnotator.new(basedic_name, user_id)
        if annotator.dictionary_exist?(basedic_name) == true
          tmp_result = annotator.terms_to_idlists(ann, opts)
          tmp_result.each_value do |term_to_idlist|
            term_to_idlist.each do |idlist|
              idlist["dictionary_name"] = basedic_name
            end
          end
          tmp_result.each_pair do |id, labels|
            if results.key?(id)
              results[id] += labels
            else
              results[id] = labels
            end
          end
        end
      end
    end
    ann["idlists"] = results

    # Return the results.
    respond_to do |format|
      format.json { render :json => ann }
    end
  end



  ###########################
  #####     METHODS     #####
  ###########################
  private

  # Create grid views for remained, disabled, and new entries.
  def get_grid_views
    ids = RemovedEntry.get_disabled_entry_idlist(@user_dictionary)

    basedic_disabled_entries = Entry.get_disabled_entries(ids)
    basedic_remained_entries = Entry.get_remained_entries(@dictionary, ids)
    userdic_new_entries      = NewEntry.get_new_entries(@user_dictionary)
    
    # 1. Remained base entries.
    if basedic_remained_entries.empty?
      grid_basedic_remained_entries = []
    else
      grid_basedic_remained_entries = initialize_grid(basedic_remained_entries, 
        :name => "basedic_remained_entries",
        :order => 'view_title',
        :order_direction => 'asc',
        :per_page => 30, )
      if params[:basedic_remained_entries] && params[:basedic_remained_entries][:selected]
        @selected = params[:basedic_remained_entries][:selected]
      end
    end

    # 2. Disabled base entries.
    if basedic_disabled_entries.empty?
      grid_basedic_disabled_entries = []
    else
      grid_basedic_disabled_entries = initialize_grid(basedic_disabled_entries,
        :name => "basedic_disabled_entries",
        :order => "view_title",
        :order_direction => "asc",
        :per_page => 30, )
      if params[:basedic_disabled_entries] && params[:basedic_disabled_entries][:selected]
        @selected = params[:basedic_disabled_entries][:selected]
      end
    end

    # 3. Prepare the Wice_Grid instance for the user_dictionary's added entries.
    if userdic_new_entries.empty?
      grid_userdic_new_entries = []
    else
      grid_userdic_new_entries = initialize_grid(userdic_new_entries, 
        :name => "userdic_new_entries",
        :order => 'view_title',
        :order_direction => 'asc',
        :per_page => 30, )
      if params[:userdic_new_entries] && params[:userdic_new_entries][:selected]
        @selected = params[:userdic_new_entries][:selected]
      end
    end

    return grid_basedic_remained_entries, grid_basedic_disabled_entries, grid_userdic_new_entries
  end

  # Create a list of entries for export.
  def build_export_entries(export_type)
    export_entries = [ ]

    if export_type == "ori"
      # Export: all entries of an original dictionary.
      export_entries = @dictionary.entries.select("view_title, label, uri")

    elsif export_type == "del"
      # Export: all deleted entries from an original dictionary.
      if not @user_dictionary.nil?
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        export_entries = @dictionary.entries.select("view_title, label, uri").find(removed_entry_ids)
      end    

    elsif export_type == "new"
      # Export: all new entries.
      if not @user_dictionary.nil?
        export_entries = @user_dictionary.new_entries.select("view_title, label, uri")
      end

    elsif export_type == "ori_del"
      # Export: entries of an original dictionary that are not deleted by a user.
      if @user_dictionary.nil?
        export_entries = @dictionary.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        export_entries = @dictionary.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri")
      end

    elsif export_type == "ori_del_new"
      # Export: a list of active entries of an original and user dictionaries.
      if @user_dictionary.nil?
        export_entries = @dictionary.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        new_entries       = @user_dictionary.new_entries  

        export_entries = @dictionary.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri") + new_entries
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
                                             label:        items[1], 
                                             uri:          items[2],
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

    time_start = Time.new
    logger.debug "... Starts to generate a simstring DB."

    db = Simstring::Writer.new(dbfile_path, 3, true, true)     # (filename, n-gram, begin/end marker, unicode)

    # @dictionary.entries.each do |entry|     #     This is too slow
    Entry.where(dictionary_id: @dictionary.id).pluck(:search_title).uniq.each do |search_title|
      db.insert(search_title)
    end

    db.close

    logger.debug "... Finishes generating a simstring DB."
    logger.debug "...... Total time elapsed: #{Time.new - time_start} seconds"
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

  # Get data parameters.
  def get_data_params1(params)
    basedic_names = params["dictionaries"].nil? ? nil : JSON.parse(params["dictionaries"])
    ann           = params["annotation"].nil?   ? nil : JSON.parse(params["annotation"])
    opts          = params["options"].nil?      ? nil : JSON.parse(params["options"])

    return basedic_names, ann, opts
  end

  # Get data parameters.
  def get_data_params2(params)
    basedic_name  = params[:id]
    ann           = params["annotation"].nil?   ? nil : JSON.parse(params["annotation"])
    opts          = params["options"].nil?      ? nil : JSON.parse(params["options"])

    return basedic_name, ann, opts
  end

end



