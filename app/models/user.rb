class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  has_many :dictionaries, dependent: :destroy
  has_many :associations
  has_many :associated_dictionaries, through: :associations, source: :dictionary

  validates :username, :presence => true, :length => {:minimum => 5, :maximum => 20}, uniqueness: true
  validates_format_of :username, :with => /\A[a-z0-9][a-z0-9_-]+\z/i
end
