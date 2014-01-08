class NewEntry < ActiveRecord::Base
  attr_accessible :label, :view_title, :search_title, :uri

  belongs_to :user_dictionary

  validates :label, :view_title, :search_title, :uri, :presence => true

  def self.get_new_entries(user_dic)
  	if user_dic.nil?
  	  entries = []
  	else
  	  entries = NewEntry.where(:user_dictionary_id => user_dic.id)
  	end
  	return entries
  end

end
