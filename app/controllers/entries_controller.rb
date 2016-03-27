class EntriesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!
 
  # Populate the new template of the a different controller, "new_entries."
  # ?? Is this right approach ??
  def new
    # Use the dictionary name as the page title.
    @page_title = params[:dictionary_id]

    @dictionary = Dictionary.find_by_title(params[:dictionary_id])
    @user_dictionary = get_user_dictionary( current_user.id, @dictionary.id )
    @new_entry = @user_dictionary.new_entries.new

    # 4. Use the new view of the new_entries controller, and use the create action in the new_entries controller too.
    render template: 'new_entries/new'
  end

  def create
    begin
      dic = Dictionary.active.editable(current_user).find_by_title(params[:dictionary_id])
      raise ArgumentError, "There is no such a dictionary in your management." if dic.nil?
      source_filepath = params[:file].tempfile.path
      target_filepath = File.join('tmp', "upload-#{dic.title}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
      FileUtils.cp source_filepath, target_filepath

      # Entry.load_from_file(target_filepath, dic)

      delayed_job = Delayed::Job.enqueue LoadEntriesFromFileJob.new(target_filepath, dic), queue: :general
      Job.create({name:"Load entries from file", dictionary_id:dic.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html {redirect_to :back}
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to :back, notice: e.message}
      end
    end
  end

  def empty
    begin
      dictionary = Dictionary.active.editable(current_user).find_by_title(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      # dictionary.empty_entries
      delayed_job = Delayed::Job.enqueue EmptyEntriesJob.new(dictionary), queue: :general
      Job.create({name:"Empty entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html{ redirect_to :back }
      end
    rescue => e
      respond_to do |format|
        format.html{ redirect_to :back, notice: e.message }
      end
    end
  end

  # # Destroy action works in two ways: 
  # #   1) remove a base dictionary entry (not from db) or
  # #   2) restore a removed base dictionary entry
  # #
  # def destroy
  #   @dictionary = Dictionary.find_by_title(params[:dictionary_id])
  #   @entry      = @dictionary.entries.find(params[:id])

  #   # 1. Get (or create) a user dictionary
  #   user_dictionary = get_user_dictionary(current_user.id, @dictionary.id)
    
  #   # 2. Remove (or restore) a base dictionary's entry
  #   if user_dictionary.removed_entries.nil?
  #     register_removed_entry(user_dictionary, @entry)
  #   else
  #     removed_entry = user_dictionary.removed_entries.where(entry_id: @entry.id).first  
      
  #     if removed_entry.nil?
  #       register_removed_entry(user_dictionary, @entry)
  #     else
  #       removed_entry.destroy
  #     end
  #   end

  #   # 3. Go to the @dictionary#show 
  #   # redirect_to @dictionary     # This command will show the FIRST page of the dictionary.
  #   redirect_to :back             # This redirect_to will show the current page :-)
  # end

  
  ###########################
  #####     Methods     #####
  ###########################

  private

  def get_user_dictionary(user_id, dictionary_id)
    user_dictionary = UserDictionary.where({ user_id: user_id, dictionary_id: dictionary_id }).first
    if user_dictionary.nil?
      user_dictionary = UserDictionary.new({ user_id: user_id, dictionary_id: dictionary_id })
      user_dictionary.save
    end

    return user_dictionary
  end

  # def register_removed_entry(user_dictionary, entry)
  #   removed_entry = user_dictionary.removed_entries.new
  #   removed_entry.entry_id = entry.id
  #   removed_entry.save
  # end

end
