class Association < ApplicationRecord
  belongs_to :user
  belongs_to :dictionary
end
