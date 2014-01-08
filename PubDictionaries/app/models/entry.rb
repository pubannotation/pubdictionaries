class Entry < ActiveRecord::Base
  # default_scope :order => 'view_title'
  
  attr_accessible :uri, :label, :view_title, :search_title
  belongs_to :dictionary

  validates :uri, :label, :view_title, :search_title, :presence => true

  # Return a list of entries except the ones specified by skip_ids.
  def self.get_remained_entries(dic, skip_ids)
  	if dic.nil?
	  entries = []
	else
	  if skip_ids.empty?
	    entries = Entry.where(:dictionary_id => dic.id)
      else
        # id not in () not work if () is empty.
        entries = Entry.where(:dictionary_id => dic.id).where("id not in (?)", skip_ids) 
      end
  	end
  	return entries
  end

  def self.get_disabled_entries(skip_ids)
  	return Entry.where(:id => skip_ids)
  end


end
