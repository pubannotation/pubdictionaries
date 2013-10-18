require 'set'
require File.join( Rails.root, '..', 'simstring-1.0/swig/ruby/simstring')


class DictionariesController < ApplicationController
 
  ###########################
  #####     ACTIONS     #####
  ###########################

  # GET /dictionaries
  # GET /dictionaries.json
  def index
    @dictionaries = Dictionary.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @dictionaries }
    end
  end


  # GET /dictionaries/1
  # GET /dictionaries/1.json
  #
  # Shows the content of an original dictionary and its corresponding user dictionary.
  #
  def show
    @dictionary = Dictionary.find(params[:id])
    @user_dictionary = @dictionary.user_dictionaries.where(user_id: current_user.id).first
         
    if params[:query] == "ori"
      # Export: all entries of an original dictionary.
      @view_entries = @dictionary.entries.select("view_title, label, uri")

    elsif params[:query] == "del"
      # Export: all deleted entries from an original dictionary.
      if @user_dictionary.nil?
        @view_entries = [ ]
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        @view_entries = @dictionary.entries.select("view_title, label, uri").find(removed_entry_ids)
      end    

    elsif params[:query] == "new"
      # Export: all new entries.
      if @user_dictionary.nil?
        @view_entries = [ ]
      else
        @view_entries = @user_dictionary.new_entries.select("view_title, label, uri")
      end

    elsif params[:query] == "ori_del"
      # Export: entries of an original dictionary that are not deleted by a user.
       if @user_dictionary.nil?
        @view_entries = @dictionary.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        @view_entries = @dictionary.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri")
      end

    elsif params[:query] == "ori_del_new"
      # Export: a list of active entries of an original and user dictionaries.
       if @user_dictionary.nil?
        @view_entries = @dictionary.entries
      else
        removed_entry_ids = RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq
        new_entries       = @user_dictionary.new_entries  

        @view_entries = @dictionary.entries.where("id NOT IN (?)", removed_entry_ids).select("view_title, label, uri") + new_entries
      end
    
    else
      # Show (default):
      #   Shows the content of a dictionary and its associated user dictionary.

      # 1. Prepares a paginated_entriesginated entry list.
      @paginated_entries = @dictionary.entries.paginate page: params[:entries_page], per_page: 15
      @n_entries         = @dictionary.entries.count

      # 2. Prepares a paginated new_entry list, andn a list of removed entries 
      #   (to be used in entries_helper.rb).
      @n_new_entries   = 0
      if not @user_dictionary.nil?
        @paginated_new_entries = @user_dictionary.new_entries.paginate page: params[:new_entries_page], per_page: 10
        @n_new_entries         = @user_dictionary.new_entries.count
        @n_removed_entries     = @user_dictionary.removed_entries.count

        @removed_entries       = Set.new( RemovedEntry.where(user_dictionary_id: @user_dictionary.id).pluck(:entry_id).uniq )
      end

    end


    respond_to do |format|
      format.html # show.html.erb
      format.tsv { send_data tsv_data(@view_entries), filename: "#{@dictionary.title}.#{params[:query]}.tsv.txt", type: "text/tsv" }
    end
  end


  # GET /dictionaries/new
  # GET /dictionaries/new.json
  def new
    @dictionary = Dictionary.new
    @dictionary.creator = current_user.email     # set the creator with the user name (email)

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @dictionary }
    end
  end


  # POST /dictionaries
  # POST /dictionaries.json
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


  # GET /dictionaries/1/edit
  # def edit
  #   @dictionary = Dictionary.find(params[:id])
  #   b_editable  = is_current_user_same_to_creator?(@dictionary)

  #   if b_editable
  #     @dictionary
  #   else
  #     redirect_to :back, notice: "This dictionary is editable by only the creator (#{@dictionary.creator})."
  #   end
  # end
  
  # PUT /dictionaries/1
  # PUT /dictionaries/1.json
  # def update
  #   @dictionary = Dictionary.find(params[:id])
  #   b_updatable = is_current_user_same_to_creator?(@dictionary)

  #   respond_to do |format|
  #     if b_updatable
  #       if @dictionary.update_attributes(params[:dictionary])
  #         format.html { redirect_to @dictionary, notice: 'Dictionary was successfully updated.' }
  #         format.json { head :no_content }
  #       else
  #         format.html { render action: "edit" }
  #         format.json { render json: @dictionary.errors, status: :unprocessable_entity }
  #       end
  #     else   
  #       format.html { redirect_to :back, notice: "This dictionary can be updated by only the creator (#{@dictionary.creator})." }
  #       # format.json { blah blah blah... }
  #     end
  #   end
  # end

  # DELETE /dictionaries/1
  # DELETE /dictionaries/1.json
  def destroy
    @dictionary = Dictionary.find(params[:id])
    
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


  ###########################
  #####     METHODS     #####
  ###########################

  private

  # Converts a collection of entries in tsv format
  def tsv_data(entries)
    entries.collect{ |e| "#{e.view_title}\t#{e.label}\t#{e.uri}\n" }.join
  end

  # Fills entries for a given dictionary
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


  # Creates a simstring db
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


  # Deletes a simstring db and associated files
  def delete_simstring_db( filename )
    dbfile_path = Rails.root.join('public/simstring_dbs', filename).to_s
    
    # Remove the main db file
    begin
      File.delete(dbfile_path)
    rescue
      # Silently ignores the error
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


end
