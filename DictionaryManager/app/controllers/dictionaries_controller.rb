require File.join( Rails.root, '..', 'simstring-1.0/swig/ruby/simstring')


class DictionariesController < ApplicationController
  ###########################
  #####     METHODS     #####
  ###########################

  # Fill entries for a given dictionary
  def fill_dic(dic_params)
    input_file  = dic_params[:file]
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
        items = line.split("\t")

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
  # Show the content of an original dictionary and its corresponding user dictionary
  #
  def show
    # 1. Prepare a paginated entry list
    @dictionary = Dictionary.find(params[:id])
    @paginated_entries = @dictionary.entries.paginate page: params[:entries_page], per_page: 15
    @n_entries = @dictionary.entries.count

    # 2. Prepare a paginated new_entry list
    @user_dictionary = @dictionary.user_dictionaries.where(user_id: current_user.id).first
    @n_new_entries = 0
    if not @user_dictionary.nil?
      @paginated_new_entries = @user_dictionary.new_entries.paginate page: params[:new_entries_page], per_page: 10
      @n_new_entries = @user_dictionary.new_entries.count
    end

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @dictionary }
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
        @dictionary.destroy
        delete_simstring_db(@dictionary.title)

        format.html { redirect_to dictionaries_url }
        format.json { head :no_content }
      else
        format.html { redirect_to :back, notice: "This dictionary can be deleted only by its creator (#{@dictionary.creator})." }
        # format.json ...
      end
    end
  end

end
