require 'elasticsearch/model'

class ExpressionsUri < ActiveRecord::Base
  belongs_to :dictionary
  belongs_to :expression
  belongs_to :uri
end
