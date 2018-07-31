class Language < ActiveRecord::Base
  attr_accessible :name, :abbreviation

  has_many :dl_associations
  has_many :dictionaries, through: :dl_associations
end
