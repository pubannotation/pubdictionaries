class AccessTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    current_user.access_tokens.create!(
      token: SecureRandom.hex(16),
      expired_at: 2.hours.from_now
    )

    redirect_back fallback_location: root_path, notice: "Access token was successfully created. It will expired in 2 hours."
  end
end
