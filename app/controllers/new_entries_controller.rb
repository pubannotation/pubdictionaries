class NewEntriesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!


  ###########################
  #####     Actions     #####
  ###########################

  # new_entries#create will be called from another controller, entries.
  def create
    user_dictionary = UserDictionary.find(params[:user_dictionary_id])
    dictionary      = Dictionary.find_by_id(user_dictionary[:dictionary_id])

    # Normalize the entry name following the normalization option of the
    # base dictionary.
    norm_opts = { lowercased:       dictionary[:lowercased], 
                  hyphen_replaced:  dictionary[:hyphen_replaced],
                  stemmed:          dictionary[:stemmed],
                }
    if params[:new_entry]
      search_title = normalize_str(params[:new_entry][:view_title], norm_opts)
      @new_entry = user_dictionary.new_entries.new(
                    { view_title:   params[:new_entry][:view_title], 
                      search_title: search_title,
                      label:        params[:new_entry][:label], 
                      uri:          params[:new_entry][:uri],
                    })
    end
    
    if @new_entry.save
      redirect_to dictionary, notice: 'A new entry was successfully created.'
    else
      redirect_to :back
    end
  end

  def destroy
    new_entry = NewEntry.find(params[:id])
    new_entry.destroy

    redirect_to :back
  end
end
