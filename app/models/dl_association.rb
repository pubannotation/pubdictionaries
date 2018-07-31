class DlAssociation < ActiveRecord::Base
  belongs_to :dictionary
  belongs_to :language
end
