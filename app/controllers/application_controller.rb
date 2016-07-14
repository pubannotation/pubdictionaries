class ApplicationController < ActionController::Base
  protect_from_forgery
  after_filter :store_location

  def store_location
    # It causes redirection loop after /user/password/edit
    #
    # # store last url - this is needed for post-login redirect to whatever the user last visited.
    # if (request.fullpath != "/users/sign_in" &&
    #   request.fullpath != "/users/sign_up" &&
    #   request.fullpath != "/users/password" &&
    #   !request.xhr?) # don't store ajax calls

    #   if request.format == "text/html" || request.content_type == "text/html"
    #     session[:previous_url] = request.fullpath
    #     session[:last_request_time] = Time.now.utc.to_i
    #   end
    # end
  end

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
