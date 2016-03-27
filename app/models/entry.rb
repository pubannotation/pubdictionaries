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

  def self.load_from_file(filename, dictionary)
    # Note: "textmode: true" option automatically converts all newline variants to \n
    # fp = File.open(file, textmode: true)

    begin
      ActiveRecord::Base.transaction do
        File.foreach(filename) do |line|
          label, uri = read_entry_line(line)
          dictionary.entries << Entry.get_by_value(label, uri) unless label.nil?
        end
        update_attribute(:entries_count)
      end
    end

    # File.delete(file)
    # Delayed::Job.enqueue(DelayedRake.new("elasticsearch:import:model", class: 'Label', scope: "diff"))
    # Delayed::Job.enqueue(DelayedRake.new("elasticsearch:import:model", class: 'Uri', scope: "diff"))
  end

  def self.read_entry_line(line)
    line.strip!

    return nil if line == ''
    return nil if line.start_with? '#'

    items = line.split(/\t/)
    return nil if items.size < 2

    items.each{|item| return nil if item.length < 2 && item.length > 32}

    [items[0], items[1]]
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

end
