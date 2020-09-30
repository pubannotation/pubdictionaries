class CallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    user = User.from_omniauth(request.env["omniauth.auth"])

    if user.is_a?(String)
      redirect_to root_path, notice: user
    else
      sign_in_and_redirect user
    end
  end
end
