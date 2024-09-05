class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    token_expiration_time = Rails.application.config.access_token_expiration_time
    current_user.access_tokens.create!(
      token: SecureRandom.hex(16),
      expired_at: token_expiration_time.from_now
    )

    redirect_back fallback_location: root_path,
                  notice: "Access token was successfully created. It will expired in #{token_expiration_time / 3600} hours."
  end
end
