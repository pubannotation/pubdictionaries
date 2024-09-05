class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    access_token = current_user.access_tokens.create!(
      token: SecureRandom.hex(16),
      expired_at: 2.hours.from_now
    )

    render json: { token: access_token.token }
  end
end
