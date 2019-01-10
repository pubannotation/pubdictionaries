class ApplicationController < ActionController::Base
  protect_from_forgery

  def after_sign_in_path_for(resource)
    valid_time_span = 120     # 120 seconds

    if session.has_key?(:last_request_time) \
       and (Time.now.utc.to_i - session[:last_request_time] < valid_time_span) \
       and session.has_key? :previous_url
      return session[:previous_url]
    else
      return root_path
    end
  end
end
