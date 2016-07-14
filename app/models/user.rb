class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :token_authenticatable

  # Setup accessible (or protected) attributes for your model
  attr_accessible :username, :email, :password, :password_confirmation, :remember_me

  has_many :dictionaries, dependent: :destroy

  validates :username, :presence => true, :length => {:minimum => 5, :maximum => 20}, uniqueness: true
  validates_format_of :username, :with => /\A[a-z0-9][a-z0-9_-]+\z/i

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

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
