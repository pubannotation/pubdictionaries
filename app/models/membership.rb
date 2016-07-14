class Membership < ActiveRecord::Base
  belongs_to :dictionary
  belongs_to :entry
end
