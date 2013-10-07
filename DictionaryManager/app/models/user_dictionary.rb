class UserDictionary < ActiveRecord::Base
  attr_accessible :dictionary_id, :user_id

  belongs_to :user
  belongs_to :dictionary

  has_many :new_entries, dependent: :destroy
  has_many :removed_entries, dependent: :destroy

  validates :dictionary_id, :user_id, presence: true
  
end
