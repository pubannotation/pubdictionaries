require 'elasticsearch/model'

class Entry < ActiveRecord::Base
  belongs_to :label
  belongs_to :uri
  has_and_belongs_to_many :dictionaries
  attr_accessible :title, :view_title, :search_title
  attr_accessible :label, :uri
  attr_accessible :label_id, :uri_id

  def self.get_by_value(label_value, uri_value)
    label = Label.get_by_value(label_value)
    uri = Uri.get_by_value(uri_value)

    entry = self.find_by_label_id_and_uri_id(label.id, uri.id)
    if entry.nil?
      entry = self.new(label_id: label.id, uri_id: uri.id)
      entry.save

      label.entries_count_up
      uri.entries_count_up
    end
    entry
  end

  def dictionaries_count_up
    increment!(:dictionaries_count)
  end

  def dictionaries_count_down
    decrement!(:dictionaries_count)
    if dictionaries_count == 0
      label.entries_count_down
      uri.entries_count_down
      destroy
    end
  end

  # Return a list of entries except the ones specified by skip_ids.
  def self.get_remained_entries(skip_ids = [])
    if skip_ids.empty?
      # Return the entries of the current dictionary.
      self.scoped 
    else
      # id not in () not work if () is empty.
      where("id not in (?)", skip_ids) 
    end
  end

  def self.get_disabled_entries(skip_ids)
    where(:id => skip_ids)
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

end
