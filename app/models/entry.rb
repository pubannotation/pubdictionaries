class Entry < ActiveRecord::Base
  belongs_to :label
  belongs_to :identifier
  has_and_belongs_to_many :dictionaries
  attr_accessible :label, :identifier
  attr_accessible :label_id, :identifier_id

  def as_json(options={})
    options||={}
    {
      label: label.value,
      id: identifier.value
    }
  end

  def self.as_tsv
    column_names = %w{label.valuesourcedb sourceid divid body created_at}

    CSV.generate(col_sep: "\t") do |tsv|
      tsv << [:label, :id]
      all.each do |entry|
        tsv << [entry.label.value, entry.identifier.value]
      end
    end
  end

  def self.get_by_value(label_value, identifier_value)
    label = Label.get_by_value(label_value)
    identifier = Identifier.get_by_value(identifier_value)

    entry = self.find_by_label_id_and_identifier_id(label.id, identifier.id)
    if entry.nil?
      entry = self.new(label_id: label.id, identifier_id: identifier.id)
      entry.save

      label.entries_count_up
      identifier.entries_count_up
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
      identifier.entries_count_down
      destroy
    end
  end

  def self.store(entry_lines)
    ActiveRecord::Base.transaction do
      count = 0
      entry_lines.each_line(entry_lines) do |line|
        label, id = Entry.read_entry_line(line)
        unless label.nil?
          dictionary.entries << Entry.get_by_value(label, id)
          count += 1
        end
      end
      dictionary.increment!(:entries_count, count)
    end
  end

  def self.read_entry_line(line)
    line.strip!

    return nil if line == ''
    return nil if line.start_with? '#'

    items = line.split(/\t/)
    return nil if items.size < 2
    return nil if items[0].length < 2 || items[0].length > 64
    return nil if items[0].empty? || items[1].empty?

    [items[0], items[1]]
  end

  def self.none
    where(:id => nil).where("id IS NOT ?", nil)
  end

end
