class RemovedEntry < ActiveRecord::Base
  attr_accessible :entry_id, :user_dictionary_id

  belongs_to :user_dictionary
  belongs_to :entry

  validates :entry_id, :uniqueness => { :scope => :user_dictionary_id }

  # Return a list of disabled base entry IDs.
  def self.get_disabled_entry_idlist(user_dic)
  	if user_dic.nil?
  	  entries = []
  	else
  	  entries = RemovedEntry.where(user_dictionary_id: user_dic.id).pluck(:entry_id).uniq
  	end
  	return entries
  end

end
