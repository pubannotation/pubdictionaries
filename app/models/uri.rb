require 'elasticsearch/model'

class Uri < ActiveRecord::Base
  has_many :entries, :dependent => :destroy
  has_many :dictionaries, :through => :entries

  attr_accessible :value

  def self.get_by_value(value)
    uri = self.find_by_value(value)
    if uri.nil?
      uri = self.new({value: value})
      uri.save
    end
    uri
  end

  def entries_count_up
    increment!(:entries_count)
  end

  def entries_count_down
    decrement!(:entries_count)
    destroy if entries_count == 0
  end

end
