class Dictionary < ActiveRecord::Base
  # default_scope :order => 'title'

  attr_accessor :file, :separator, :sort
  attr_accessible :creator, :description, :title, :stemmed, :lowercased, :hyphen_replaced, :public, :file, :separator, :sort

  belongs_to :user

  has_many :entries, :dependent => :destroy
  has_many :user_dictionaries, :dependent => :destroy

  validates :creator, :description, :title, :presence => true
  validates :title, uniqueness: true
  validates_inclusion_of :public, :in => [true, false]     # :presence fails when the value is false.


  # Overrides original to_param so that it returns title, not ID, for constructing URLs. 
  # Use Model#find_by_title() instead of Model.find() in controllers.
  def to_param
    title
  end

  # Return a list of dictionaries that are either public or belonging to the logged in user.
  def self.get_showable_dictionaries(user_id)
    Dictionary.where('public = ? OR user_id = ?', true, user_id)
  end


end
