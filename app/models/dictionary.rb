require 'simstring'

class Dictionary < ActiveRecord::Base
  include StringManipulator

  attr_accessible :name, :description, :user_id, :language
  attr_accessible :active
  attr_accessible :entries_num

  belongs_to :user

  has_many :membership, :dependent => :destroy
  has_many :entries, :through => :membership

  has_many :jobs, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true 
  validates :description, presence: true
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /^[^\.]*$/,
                      :message => "should not contain dot!"

  SSDB_DIR = "db/simstring/"

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  scope :active, where(active: true)

  scope :mine, -> (user) {
    if user.nil?
      none
    else
      where('user_id = ?', user.id)
    end
  }

  scope :editable, -> (user) {
    if user.nil?
      none
    else
      where('user_id = ?', user.id)
    end
  }

  def editable?(user)
    user && user_id == user.id
  end

  def get_entry(label, id)
    entries.find_by(label:label, identifier: id)
  end

  def add_entry(label, id)
    e = Entry.get_by_value(label, id)
    if e.nil?
      norm1 = Entry.normalize1(label)
      norm2 = Entry.normalize2(label)
      e = Entry.create(label:label, identifier:id, norm1:norm1, norm2:norm2, label_length:label.length, dictionaries_num:1)
    end

    unless entries.include?(e)
      # entries << e
      ActiveRecord::Base.connection.execute(%{INSERT INTO "memberships" ("created_at", "dictionary_id", "entry_id", "updated_at") VALUES (now(), #{self.id}, #{e.id}, now()) returning "id"})

      increment!(:entries_num)
      e.increment!(:dictionaries_num)
    end
  end

  def destroy_entry(e)
    if entries.include?(e)
      entries.destroy(e)
      decrement!(:entries_num)
      e.decrement!(:dictionaries_num)
      e.destroy if e.dictionaries_num == 0
    end
  end

  def add_new_entries(pairs)
    ActiveRecord::Base.transaction do
      new_entries = pairs.map do |label, id|
        begin
          norm1 = Entry.normalize1(label)
          norm2 = Entry.normalize2(label)
          Entry.new(label:label, identifier:id, norm1: norm1, norm2: norm2, label_length:label.length, dictionaries_num:1, flag:true)
        rescue => e
          raise ArgumentError, "The entry, [#{label}, #{id}], is rejected: #{e}."
        end
      end

      r = Entry.import new_entries, validate: false
      raise "Import error" unless r.failed_instances.empty?

      new_eids = Entry.where(flag: true).pluck(:id)
      new_records = new_eids.map{|eid| "(now(), #{self.id}, #{eid}, now())"}
      ActiveRecord::Base.connection.execute(%{INSERT INTO "memberships" ("created_at", "dictionary_id", "entry_id", "updated_at") VALUES } + new_records.join(", "))
      Entry.where(flag: true).update_all(flag: false)

      increment!(:entries_num, new_entries.length)
    end
  end

  def add_entries(entries)
    ActiveRecord::Base.transaction do
      # self.entries += entries
      add_records = entries.map{|e| "(now(), #{self.id}, #{e.id}, now())"}
      ActiveRecord::Base.connection.execute(%{INSERT INTO "memberships" ("created_at", "dictionary_id", "entry_id", "updated_at") VALUES } + add_records.join(", "))

      # entries.update_all('dictionaries_num = dictionaries_num + 1')
      entries.each{|e| e.increment!(:dictionaries_num)}

      increment!(:entries_num, entries.length)
    end
  end

  def empty_entries
    ActiveRecord::Base.transaction do
      entries.update_all('dictionaries_num = dictionaries_num - 1')
      Entry.delete(Entry.joins(:membership).where("memberships.dictionary_id" => self.id, dictionaries_num: 0).pluck(:id))

      entries.update_all(flag:true)
      entries.delete_all
      Entry.where(flag:true).update_all(flag:false)

      update_attribute(:entries_num, 0)
    end
  end

  def self.find_ids_by_labels(labels, dictionaries = [], threshold = 0.85, rich = false)
    ssdbs = dictionaries.inject({}) do |h, dic|
      h[dic.name] = Simstring::Reader.new(dic.ssdb_path)
      h[dic.name].measure = Simstring::Jaccard
      h[dic.name].threshold = threshold
      h
    end

    labels.inject({}) do |h, label|
      h[label] = Entry.search_term(label, dictionaries, ssdbs, threshold)
      h[label].map!{|entry| entry[:identifier]} unless rich
      h
    end
  end

  def ssdb_exist?
    File.exists? ssdb_path
  end

  def ssdb_dir
    Dictionary::SSDB_DIR + self.name
  end

  def ssdb_path
    Rails.root.join(ssdb_dir, "simstring.db").to_s
  end

  def compile
    FileUtils.mkdir_p(ssdb_dir) unless Dir.exist?(ssdb_dir)
    # Simstring::Writer.new(db_filename, n-gram, begin/end marker, unicode)
    db = Simstring::Writer.new  ssdb_path, 3, false, true

    # dictionary.entries.each do |entry|     # This is too slow.
    # Entry.where(dictionary_id: dictionary.id).pluck(:norm2).uniq.each do |search_title|
    self.entries.pluck(:norm2).uniq.each {|norm2| db.insert norm2}
    # Entry.where(dictionary_id: self.id).pluck(:norm2).uniq.each {|norm2| db.insert norm2}

    db.close
  end

  def compiled_at
    File.mtime(ssdb_path).utc if ssdb_exist?
  end

  def compilable?
    (entries_num > 0) && (!ssdb_exist? || (compiled_at - updated_at < 0))
  end

  def destroy
    empty_entries
    self.destroy
  end
end
