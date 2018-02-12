class Association < ActiveRecord::Base
  belongs_to :user
  belongs_to :dictionary
  # attr_accessible :title, :body
end
