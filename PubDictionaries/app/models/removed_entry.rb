class RemovedEntry < ActiveRecord::Base
  attr_accessible :entry_id, :user_dictionary_id

  belongs_to :user_dictionary
  belongs_to :entry

  validates :entry_id, :uniqueness => { :scope => :user_dictionary_id }
end
