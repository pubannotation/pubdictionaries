class SessionsController < Devise::SessionsController
  skip_before_filter :verify_authenticity_token
  respond_to :html, :json

  def create
    email     = params[:user][:email]
    password  = params[:user][:password]

    respond_to do |format|
      format.html do super end
      format.json do
        if email.nil? or password.nil?
          render :status=>400, :json=>{:message=>"The request must contain the user email and password."}
          return
        end

        @user=User.find_by_email(email.downcase)
     
        if @user.nil?
          logger.info("User #{email} failed signin, user cannot be found.")
          render :status=>401, :json=>{:message=>"Invalid email or passoword."}
          return
        end
     
        # http://rdoc.info/github/plataformatec/devise/master/Devise/Models/TokenAuthenticatable
        @user.ensure_authentication_token!
     
        if not @user.valid_password?(password)
          logger.info("User #{email} failed signin, password \"#{password}\" is invalid")
          render :status=>401, :json=>{:message=>"Invalid email or password."}
        else
          render :status=>200, :json=>{:auth_token=>@user.authentication_token}
        end
      end
    end
  end
 
  def destroy
    respond_to do |format|
      format.html do super end
      format.json do
        @user=User.find_by_authentication_token(params[:auth_token])
        if @user.nil?
          logger.info("Token not found.")
          render :status=>404, :json=>{:message=>"Invalid token."}
        else
          # Reset the auth_token!
          # @user.reset_authentication_token!
          #
          # Remove the auth_token!
          @user.authentication_token = nil
          @user.save
          render :status=>200, :json=>{:auth_token=>params[:auth_token]}
        end
      end
    end
  end
 
end