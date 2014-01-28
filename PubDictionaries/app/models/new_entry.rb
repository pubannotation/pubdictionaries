class NewEntry < ActiveRecord::Base
  attr_accessible :label, :view_title, :search_title, :uri

  belongs_to :user_dictionary

  validates :label, :view_title, :search_title, :uri, :presence => true

  def self.get_new_entries()
    self.scoped
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

end
