class Entry < ActiveRecord::Base
  # default_scope :order => 'view_title'
  
  attr_accessible :uri, :label, :view_title, :search_title
  belongs_to :dictionary

  validates :uri, :view_title, :search_title, :presence => true

  # Return a list of entries except the ones specified by skip_ids.
  def self.get_remained_entries(skip_ids = [])
    if skip_ids.empty?
      # Return the entries of the current dictionary.
      self.scoped 
    else
      # id not in () not work if () is empty.
      where("id not in (?)", skip_ids) 
    end
  end

  def self.get_disabled_entries(skip_ids)
    where(:id => skip_ids)
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end


end
