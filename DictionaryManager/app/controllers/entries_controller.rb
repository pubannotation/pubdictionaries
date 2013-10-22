class EntriesController < ApplicationController
 
  ###########################
  #####     Actions     #####
  ###########################

  # Populate the new template of the a different controller, "new_entries."
  # ?? Is this right approach ??
  def new
    # 1. Get the current dictionary
    @dictionary = Dictionary.find(params[:dictionary_id])

    # 2. Get (or create) a user dictionary belongs_to @dictionary and user
    @user_dictionary = get_user_dictionary( current_user.id, @dictionary.id )
    
    # 3. Create a new new_entry for @user_dictionary
    @new_entry = @user_dictionary.new_entries.new

    # 4. Use the new view of the new_entries controller, and use the create action in the new_entries controller too.
    render template: 'new_entries/new'
  end

  
  # Destroy action works in two ways: 
  #   1) remove a base dictionary entry (not from db) or
  #   2) restore a removed base dictionary entry
  #
  def destroy
    @dictionary = Dictionary.find(params[:dictionary_id])
    @entry      = @dictionary.entries.find(params[:id])

    # 1. Get (or create) a user dictionary
    user_dictionary = get_user_dictionary(current_user.id, @dictionary.id)
    
    # 2. Remove (or restore) a base dictionary's entry
    if user_dictionary.removed_entries.nil?
      register_removed_entry(user_dictionary, @entry)
    else
      removed_entry = user_dictionary.removed_entries.where(entry_id: @entry.id).first  
      
      if removed_entry.nil?
        register_removed_entry(user_dictionary, @entry)
      else
        removed_entry.destroy
      end
    end

    # 3. Go to the @dictionary#show 
    # redirect_to @dictionary     # This command will show the FIRST page of the dictionary.
    redirect_to :back             # This redirect_to will show the current page :-)
  end

  
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

  def register_removed_entry(user_dictionary, entry)
    removed_entry = user_dictionary.removed_entries.new
    removed_entry.entry_id = entry.id
    removed_entry.save
  end



end
