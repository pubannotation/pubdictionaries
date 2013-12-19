require 'set'


require File.join( Rails.root, '..', 'simstring-1.0/swig/ruby/simstring')
require File.join( File.dirname( __FILE__ ), 'text_annotations/text_annotator' )


class DictionariesController < ApplicationController
  # Require authentication for all actions except :index and :show
  before_filter :authenticate_user!, except: [:index, :show, :text_annotations]
  # Disable CSRF check for actions 
  skip_before_filter :verify_authenticity_token, :only => [:text_annotations], :if => Proc.new { |c| c.request.format == 'application/json' }


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


  #
  # Shows the content of an original dictionary and its corresponding user dictionary.
  #
  def show
    # Gets the selected dictionary and the user dictionary connected to it.
    @dictionary       = Dictionary.find_by_title(params[:id])
    if user_signed_in?
      @user_dictionary  = @dictionary.user_dictionaries.where(user_id: current_user.id).first
    end
         
    # Export? or Show?
    if ["ori", "del", "new", "ori_del", "ori_del_new"].include? params[:query]
      # Prepares data for export.
      @export_entries = build_export_entries(params[:query])

    else
      # Prepares paginated (original) entries.
      @pg_entries = @dictionary.search_entries( params[:entry_search], 
                                                params[:entry_sort], 
                                                params[:entries_page] )

      # Prepares paginated new_entries and a set of removed entry IDs.
      if not @user_dictionary.nil?
        @pg_new_entries  = @user_dictionary.search_new_entries( params[:new_entry_search], 
                                                                params[:new_entry_sort], 
                                                                params[:new_entries_page] )
        
        @removed_entries = Set.new( RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq )
      end
    end

    respond_to do |format|
      format.html # show.html.erb
      format.tsv { send_data tsv_data(@export_entries), 
                             filename: "#{@dictionary.title}.#{params[:query]}.tsv", 
                            type: "text/tsv" }
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
    @dictionary = Dictionary.find_by_title(params[:id])
    
    respond_to do |format|
      if is_current_user_same_to_creator?(@dictionary)
        ## This is too slow.
        # @dictionary.destroy

        ## Much faster than destroy.
        # Deletes entries of the dictionary.
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
  def text_annotations
    basedic_name = params[:id]
    ann          = params["annotation"].nil? ? nil : JSON.parse(params["annotation"])
    opts         = params["options"].nil?    ? nil : JSON.parse(params["options"])


    # 1. Get the user ID if the given email/password is valid.
    user_id = get_user_id(params["user"])

    # 2. Perform a specified task.
    case user_id
    when :invalid
      ann["error"] = {"message" => "Invalid email or password"}
      result = ann
    when :guest
      annotator = TextAnnotator.new(basedic_name, nil)
      result    = perform_annotation_task(annotator, ann, opts)
    else
      annotator = TextAnnotator.new(basedic_name, user_id)
      result    = perform_annotation_task(annotator, ann, opts)
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

  # Get the user ID for a given email/password pair.
  def get_user_id(email_password)
    if email_password.nil? or email_password["email"] == ""
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

  #Perform a specified task.
  def perform_annotation_task(annotator, ann, opts)
    case opts["task"]
    when "annotation"     # Annotate an input text (exact, approximate).
      return annotator.annotate(ann, opts)
    when "id_to_label"    # Retrieve the human readable labels for given IDs. 
      return annotator.id_to_label(ann, opts)
    else                  # Return the original annotation instance.
      returnann
    end
  end

end
