class RemovedEntry < ActiveRecord::Base
  attr_accessible :entry_id, :user_dictionary_id

  belongs_to :user_dictionary, :touch => true
  belongs_to :entry

  validates :entry_id, :uniqueness => { :scope => :user_dictionary_id }

  # Return a list of disabled base entry IDs.
  def self.get_disabled_entry_idlist
 	  pluck(:entry_id).uniq
  end

end
