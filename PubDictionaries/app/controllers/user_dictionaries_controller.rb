class UserDictionariesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!

  def index_for_owner
  	user_dics = UserDictionary.get_user_dictionaries_by_owner(params[:base_dic])
    @grid_user_dictionaries = get_user_dictionaries_grid_view(user_dics)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: user_dics }
    end
  end


  private

  # Create grid views for dictionaries
  def get_user_dictionaries_grid_view(user_dics)
    grid_user_dictionaries_view = initialize_grid(user_dics,
      :name => "user_dictionaries_list",
      :per_page => 30, )
    # if params[:dictionaries_list] && params[:dictionaries_list][:selected]
    #   @selected = params[:dictionaries_list][:selected]
    # end
  
    return grid_user_dictionaries_view
  end

 
end
