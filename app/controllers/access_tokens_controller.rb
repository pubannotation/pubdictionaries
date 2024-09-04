class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    token_expires_in = Doorkeeper.configuration.access_token_expires_in

    token = Doorkeeper::AccessToken.create!(
      resource_owner_id: current_user.id,
      expires_in: token_expires_in
    )

    render json: { token: token.token, expires_in: (token_expires_in / 3600) }
  end
end
