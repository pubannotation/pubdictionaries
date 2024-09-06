class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    token = current_user.create_access_token!

    redirect_back fallback_location: root_path,
                  notice: "Access token was successfully created. It will expired in #{token.expired_at}."
  end
end
