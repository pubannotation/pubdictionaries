require 'elasticsearch/model'

class Uri < ActiveRecord::Base
  has_and_belongs_to_many :expressions
  has_many :expressions_uris
  has_many :dictionaries, through: :expressions_uris
end
