class DlAssociation < ApplicationRecord
  belongs_to :dictionary
  belongs_to :language
end
