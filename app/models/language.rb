class Language < ActiveRecord::Base
  has_many :dl_associations
  has_many :dictionaries, through: :dl_associations
end
