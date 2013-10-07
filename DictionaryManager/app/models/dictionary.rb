class Dictionary < ActiveRecord::Base
  default_scope :order => 'title'
  
  attr_accessor :file     # virtual attribute for uploading a file
  attr_accessible :creator, :description, :title, :file, :stemmed, :lowercased, :hyphen_replaced

  belongs_to :user

  has_many :entries, :dependent => :destroy
  has_many :user_dictionaries, :dependent => :destroy

  validates :creator, :description, :title, :presence => true
  validates :title, uniqueness: true

end
