class NewEntry < ActiveRecord::Base
  attr_accessible :label, :view_title, :search_title, :uri

  belongs_to :user_dictionary

  validates :label, :view_title, :search_title, :uri, :presence => true
end
