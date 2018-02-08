class UsersController < ApplicationController
  before_filter :is_root_user?, only: :index
  
  def index
    @users = User.all.page(params[:page]) 
  end

  def show
    @user = User.find_by_username(params[:name])
    @dictionaries_grid = initialize_grid(Dictionary.mine(@user),
      :order => 'created_at',
      :order_direction => 'desc',
      :per_page => 20
    )
  end
end
