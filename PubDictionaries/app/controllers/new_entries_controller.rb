class NewEntriesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!


  ###########################
  #####     Actions     #####
  ###########################

  # new_entries#create will be called from another controller, entries.
  def create
    # 1. Create a new new_entry for the user_dictionary
    user_dictionary = UserDictionary.find(params[:user_dictionary_id])

    dictionary = Dictionary.find_by_id(user_dictionary[:dictionary_id])
    norm_opts = { lowercased:       dictionary[:lowercased], 
                  hyphen_replaced:  dictionary[:hyphen_replaced],
                  stemmed:          dictionary[:stemmed],
                }

    @new_entry = user_dictionary.new_entries.new(
                  { view_title:   params[:new_entry][:view_title], 
                    search_title: normalize_str(params[:new_entry][:view_title], norm_opts), 
                    label:        params[:new_entry][:label], 
                    uri:          params[:new_entry][:uri],
                  })
    
    # 2. Find the dictionary that involves the current user dictionary
    @dictionary = Dictionary.find_by_id(user_dictionary.dictionary_id)

    # 3. Send a response
    if @new_entry.save
      redirect_to @dictionary, notice: 'New entry was successfully created.'
    else
      render action: "new"
    end
  end

  def destroy
    @new_entry = NewEntry.find(params[:id])

    # Find the dictionary, which @new_entry belongs to, for redirection
    user_dictionary = UserDictionary.find(@new_entry.user_dictionary_id)
    dictionary      = Dictionary.find_by_title(user_dictionary.dictionary_id)

    # Destroy a new_entry in the user_dictionary
    @new_entry.destroy

    # Redirect to the dictionary page
    redirect_to dictionary
  end
end
