class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :token_authenticatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me

  has_many :dictionaries, dependent: :destroy
  has_many :user_dictionaries, dependent: :destroy

  # Get the user ID for the given email/password pair.
  def self.get_user_id(params)
    if params.nil? or params["email"] == nil or params["email"] == ""
      return nil
    else
      # Find the user that first matches to the condition.
      user = User.find_by_email(params["email"])     

      if user and user.valid_password?(params["password"])
        return user.id
      else
        return :invalid
      end
    end
  end

  
end
