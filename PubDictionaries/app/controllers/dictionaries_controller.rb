require 'set'


require File.join( Rails.root, '..', 'simstring-1.0/swig/ruby/simstring')
require File.join( File.dirname( __FILE__ ), 'text_annotations/text_annotator' )


class DictionariesController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_filter :authenticate_user!, 
    except: [:index, :show, :annotate_text, :ids_to_labels, :terms_to_idlists]

  # Disable CSRF check for specific actions.
  skip_before_filter :verify_authenticity_token, 
    :only => [:annotate_text, :ids_to_labels, :terms_to_idlists], 
    :if => Proc.new { |c| c.request.format == 'application/json' }


  ###########################
  #####     ACTIONS     #####
  ###########################

  def index
    @dictionaries = Dictionary.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @dictionaries }
    end
  end

  # Show the content of an original dictionary and its corresponding user dictionary.
  def show
    # Get the selected dictionary and the corresponding user dictionary.
    @dictionary    = Dictionary.find_by_title(params[:id])
    if user_signed_in?
      @user_dictionary = @dictionary.user_dictionaries.find_by_user_id(current_user.id)
    else
      @user_dictionary = nil
    end

    # Replace the page title with the dictionary name
    @page_title = @dictionary.title

     
    # Export? or Show?
    if ["ori", "del", "new", "ori_del", "ori_del_new"].include? params[:query]
      # Prepares data for export.
      @export_entries = build_export_entries(params[:query])

    else
      if @user_dictionary
        basedic_disabled_entries_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        basedic_disabled_entries     = Entry.where(:id => basedic_disabled_entries_ids)
        if basedic_disabled_entries_ids.empty?
          basedic_remained_entries     = Entry.where(:dictionary_id => @dictionary.id)
        else
          basedic_remained_entries     = Entry.where(:dictionary_id => @dictionary.id).where("id not in (?)", basedic_disabled_entries_ids)   # id not in () not work if () is empty.
        end
        userdic_new_entries          = NewEntry.where(:user_dictionary_id => @user_dictionary.id)
      else
        basedic_disabled_entries     = nil
        basedic_remained_entries     = Entry.where(:dictionary_id => @dictionary.id)
        userdic_new_entries          = nil
      end

      # 1. Disabled base entries.
      if basedic_disabled_entries.nil?
        @grid_basedic_disabled_entries = nil
      else
        @grid_basedic_disabled_entries = initialize_grid(basedic_disabled_entries,
          :name => "basedic_disabled_entries",
          :order => "view_title",
          :order_direction => "asc",
          :per_page => 30, )
        if params[:basedic_disabled_entries] && params[:basedic_disabled_entries][:selected]
          @selected = params[:basedic_disabled_entries][:selected]
        end
      end

      # 2. Remained base entries.
      if basedic_remained_entries.nil?
        @grid_basedic_remained_entries = nil
      else
        @grid_basedic_remained_entries = initialize_grid(basedic_remained_entries, 
          :name => "basedic_remained_entries",
          :order => 'view_title',
          :order_direction => 'asc',
          :per_page => 30, )
        if params[:basedic_remained_entries] && params[:basedic_remained_entries][:selected]
          @selected = params[:basedic_remained_entries][:selected]
        end
      end

      # 3. Prepare the Wice_Grid instance for the user_dictionary's added entries.
      if userdic_new_entries.nil?
        @grid_userdic_new_entries = nil
      else
        @grid_userdic_new_entries = initialize_grid(userdic_new_entries, 
          :name => "userdic_new_entries",
          :order => 'view_title',
          :order_direction => 'asc',
          :per_page => 30, )
        if params[:userdic_new_entries] && params[:userdic_new_entries][:selected]
          @selected = params[:userdic_new_entries][:selected]
        end
      end
    end

    respond_to do |format|
      format.html # show.html.erb
      format.tsv { send_data tsv_data(@export_entries), 
        filename: "#{@dictionary.title}.#{params[:query]}.tsv", 
        type: "text/tsv" }
    end
  end

  # Disable (or enable) multiple selected entries (from the base dictionary).
  def disable_entries
    dictionary       = Dictionary.find_by_title(params[:id])
    disabled_entries = get_user_dictionary(current_user.id, dictionary.id).removed_entries
    
    if params["commit"] == "Disable selected entries" \
       and params.has_key? :basedic_remained_entries \
       and params[:basedic_remained_entries].has_key? :selected
      
      params[:basedic_remained_entries][:selected].each do |id|
        entry = dictionary.entries.find(id)
        if not disabled_entries.exists?(entry_id: entry.id)
          register_disabled_entry(disabled_entries, entry)
        end
      end
    end

    if params["commit"] == "Enable selected entries" \
       and params.has_key? :basedic_disabled_entries \
       and params[:basedic_disabled_entries].has_key? :selected

      params[:basedic_disabled_entries][:selected].each do |id|
        entry = dictionary.entries.find(id)

        if disabled_entries.exists?(entry_id: entry.id)
          disabled_entries.where(entry_id: entry.id).first.destroy
        end
      end
    end

    redirect_to :back   
  end

  # Remove multiple selected entries (from the user dictionary).
  def remove_entries
    dictionary       = Dictionary.find_by_title(params[:id])
    user_dictionary  = get_user_dictionary(current_user.id, dictionary.id)

    if not params[:userdic_new_entries][:selected].nil?
      params[:userdic_new_entries][:selected].each do |id|
        entry = user_dictionary.new_entries.find(id)
        if not entry.nil?
          entry.destroy
        end
      end
    end

    redirect_to :back   
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
    user = User.find(current_user.id)

    @dictionary = user.dictionaries.new( params[:dictionary] )
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

  def destroy
    base_dic  = Dictionary.find_by_title(params[:id])
    user_dics = UserDictionary.where(:dictionary_id => base_dic.id)

    if current_user_is_creator?(dictionary) and no_user_entries?(user_dics)
      # Delete entries     # @dictionary.destroy - Too slow due to the validation.
      Entry.where("dictionary_id = ?", @dictionary.id).delete_all

      # Delete user empty dictionaries associated to the base dictionary.
      user_dics.each do |udic|
        udic.destroy
      end
    end

    @dictionary = Dictionary.find_by_title(params[:id])
    
    respond_to do |format|
      if current_user_is_creator?(@dictionary)

        # @dictionary.destroy   # Too slow
        Entry.where("dictionary_id = ?", @dictionary.id).delete_all

        # Deletes new and removed entries of the associated user dictionaries.
        @dictionary.user_dictionaries.all.each do |userdic|
          NewEntry.where("user_dictionary_id = ?", userdic.id).delete_all
          RemovedEntry.where("user_dictionary_id = ?", userdic.id).delete_all
        end

        # Deletes the associated user dictionaries.
        UserDictionary.where("dictionary_id = ?", @dictionary.id).delete_all

        # Deletes the dictionary.
        Dictionary.where("id = ?", @dictionary.id).delete_all

        # Deletes the associated SimString DB.
        delete_simstring_db(@dictionary.title)

        format.html { redirect_to dictionaries_url }
        format.json { head :no_content }
      else
        format.html { redirect_to :back, notice: "This dictionary can be deleted only by its creator (#{@dictionary.creator})." }
        # format.json ...
      end
    end
  end


  # Annotate a given text using a base dictionary (and its corresponding user dictionary).
  def annotate_text
    basedic_name, ann, opts = get_data_params(params)
    user_id = get_user_id(params["user"])

    case user_id
    when :invalid
      ann["error"] = {"message" => "Invalid email or password"}
      result       = ann
    when :guest
      annotator    = TextAnnotator.new(basedic_name, nil)
      result       = annotator.annotate(ann, opts)
    else
      annotator    = TextAnnotator.new(basedic_name, user_id)
      result       = annotator.annotate(ann, opts)
    end

    # Return the result.
    respond_to do |format|
      format.json { render :json => result }
    end
  end

  # Return a list of labels for a given list of IDs.
  def ids_to_labels
    basedic_name, ann, opts = get_data_params(params)
    user_id = get_user_id(params["user"])

    case user_id 
    when :invalid
      ann["error"] = {"message" => "Invalid email or password"}
      result       = ann
    when :guest
      annotator    = TextAnnotator.new(basedic_name, nil)
      result       = annotator.ids_to_labels(ann, opts)
    else
      annotator    = TextAnnotator.new(basedic_name, user_id)
      result       = annotator.ids_to_labels(ann, opts)
    end

    # Return the result.
    respond_to do |format|
      format.json { render :json => result }
    end
  end

  # For a given list of terms, find the list of IDs for each of them.
  #
  # * Input  : [term_1, term_2, ... ,term_n]
  # * Output : {"term_1"=>[ID_1, ID_24, ID432], "term_2"=>[ ... ], ... }
  #
  def terms_to_idlists
    basedic_name, ann, opts = get_data_params(params)
    user_id = get_user_id(params["user"])

    case user_id 
    when :invalid
      ann["error"] = {"message" => "Invalid email or password"}
      result       = ann
    when :guest
      annotator    = TextAnnotator.new(basedic_name, nil)
      result       = annotator.terms_to_idlists(ann, opts)
    else
      annotator    = TextAnnotator.new(basedic_name, user_id)
      result       = annotator.terms_to_idlists(ann, opts)
    end

    # Return the result.
    respond_to do |format|
      format.json { render :json => result }
    end
  end



  ###########################
  #####     METHODS     #####
  ###########################
  private

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
  def get_data_params(params)
    basedic_name = params[:id]
    ann          = params["annotation"].nil? ? nil : JSON.parse(params["annotation"])
    opts         = params["options"].nil?    ? nil : JSON.parse(params["options"])

    return basedic_name, ann, opts
  end

  # Get the user ID for a given email/password pair.
  def get_user_id(email_password)
    if email_password.nil? or email_password["email"] == nil or email_password["email"] == ""
      return :guest
    else
      # Find the user that first matches to the condition.
      user = User.find_by_email(email_password["email"])     

      if user and user.valid_password?(email_password["password"])
        return user.id
      else
        return :invalid
      end
    end
  end

  def get_user_dictionary(user_id, dictionary_id)
    user_dictionary = UserDictionary.where({ user_id: user_id, dictionary_id: dictionary_id }).first
    if user_dictionary.nil?
      user_dictionary = UserDictionary.new({ user_id: user_id, dictionary_id: dictionary_id })
      user_dictionary.save
    end

    user_dictionary
  end

  def register_disabled_entry(disabled_entries, entry)
    disabled_entry = disabled_entries.new
    disabled_entry.entry_id = entry.id
    disabled_entry.save
  end

  # True if none of user dictionaries has new or disabled entries; otherwise, false.
  def no_user_entries?(user_dics)
    user_dics.each do |udic|
      new_entries      = NewEntry.find_by_user_dictionary_id(udic.id)     # Find the first one (faster than where).
      disabled_entries = RemovedEntry.find_by_user_dictionary_id(udic.id)

      if not new_entries.nil? or not disabled_entries.nil?
        return false
      end
    end

    return true
  end

end



