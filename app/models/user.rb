class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, :omniauth_providers => [:google_oauth2]

  has_many :dictionaries, dependent: :destroy
  has_many :associations
  has_many :associated_dictionaries, through: :associations, source: :dictionary

  validates :username, :presence => true, :length => {:minimum => 5, :maximum => 20}, uniqueness: true
  validates_format_of :username, :with => /\A[a-z0-9][a-z0-9_-]+\z/i

  def self.from_omniauth(auth)
    user = User.find_by_email(auth.info.email)
    return user if user and user.confirmed?

    user = User.new(email: auth.info.email, username: auth.info.name, password: Devise.friendly_token[0,20])
    if user.save
      user
    else
      "username(#{auth.info.name}) is invalid."
    end
  end
end
