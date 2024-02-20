class Tag < ApplicationRecord
  belongs_to :dictionary
  has_many :entry_tags
  has_many :entries, through: :entry_tags
end
