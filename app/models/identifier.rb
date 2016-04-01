require 'elasticsearch/model'

class Identifier < ActiveRecord::Base
  has_many :entries
  has_many :dictionaries, :through => :entries

  attr_accessible :value

  def self.get_by_value(value)
    identifier = self.find_by_value(value)
    if identifier.nil?
      identifier = self.new({value: value})
      identifier.save
    end
    identifier
  end

  def entries_count_up
    increment!(:entries_count)
  end

  def entries_count_down
    decrement!(:entries_count)
    destroy if entries_count == 0
  end

end
