class Entry < ActiveRecord::Base
  default_scope :order => 'view_title'
  
  attr_accessible :uri, :label, :view_title, :search_title
  belongs_to :dictionary

  validates :uri, :label, :view_title, :search_title, :presence => true

end
