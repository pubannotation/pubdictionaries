require 'simstring'

class Dictionary < ActiveRecord::Base
  include StringManipulator

  belongs_to :user
  has_many :associations
  has_many :associated_managers, through: :associations, source: :user
  has_many :entries, :dependent => :destroy
  has_many :jobs, :dependent => :destroy

  attr_accessible :name, :description, :user_id
  attr_accessible :entries_num

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

  scope :mine, -> (user) {
    if user.nil?
      none
    else
      includes(:associations).where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
    end
  }

  scope :editable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      includes(:associations).where('dictionaries.user_id = ? OR associations.user_id = ?', user.id, user.id)
    end
  }

  scope :administerable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      where('user_id = ?', user.id)
    end
  }

  def editable?(user)
    user && (user.admin? || user_id == user.id || associated_managers.include?(user))
  end

  def administerable?(user)
    user && (user.admin? || user_id == user.id)
  end

  def get_entry(label, id)
    entries.find_by(label:label, identifier: id)
  end

  def create_addition(label, id)
    e = entries.find_by_label_and_identifier(label, id)
    if e.nil?
      norm1 = Entry.normalize1(label)
      norm2 = Entry.normalize2(label)
      entries.create(label:label, identifier:id, norm1:norm1, norm2:norm2, label_length:label.length, mode:Entry::MODE_ADDITION)
      increment!(:entries_num)
    end
    update_tmp_ssdb
  end

  def create_deletion(entry)
    entry.update_attribute(:mode, Entry::MODE_DELETION)
    decrement!(:entries_num)
  end

  def undo_entry(entry)
    if entry.mode == Entry::MODE_ADDITION
      entry.delete
      decrement!(:entries_num)
    elsif entry.mode == Entry::MODE_DELETION
      entry.update_attribute(:mode, Entry::MODE_NORMAL)
      increment!(:entries_num)
    end

    update_tmp_ssdb
  end

  def update_tmp_ssdb
    FileUtils.mkdir_p(ssdb_dir) unless Dir.exist?(ssdb_dir)
    db = Simstring::Writer.new tmp_ssdb_path, 3, false, true
    self.entries.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    db.close
  end

  def num_addition
    entries.where(mode:Entry::MODE_ADDITION).count
  end

  def num_deletion
    entries.where(mode:Entry::MODE_DELETION).count
  end

  def destroy_entry(e)
    if entries.include?(e)
      entries.destroy(e)
      decrement!(:entries_num)
      e.decrement!(:dictionaries_num)
      e.destroy if e.dictionaries_num == 0
    end
  end

  def add_entries(pairs, normalizer1 = nil, normalizer2 = nil)
    ActiveRecord::Base.transaction do
      new_entries = pairs.map do |label, id|
        begin
          norm1 = Entry.normalize1(label, normalizer1)
          norm2 = Entry.normalize2(label, normalizer2)
          Entry.new(label:label, identifier:id, norm1: norm1, norm2: norm2, label_length:label.length, dictionary_id: self.id)
        rescue => e
          raise ArgumentError, "The entry, [#{label}, #{id}], is rejected: #{e}."
        end
      end

      r = Entry.import new_entries, validate: false
      raise "Import error" unless r.failed_instances.empty?

      increment!(:entries_num, new_entries.length)
    end
  end

  def empty_entries
    ActiveRecord::Base.transaction do
      Entry.delete(Entry.where(dictionary_id: self.id).pluck(:id))
      update_attribute(:entries_num, 0)
    end
  end

  def self.find_dictionaries_from_params(params)
    dicnames = if params.has_key?(:dictionaries)
      params[:dictionaries]
    elsif params.has_key?(:dictionary)
      params[:dictionary]
    elsif params.has_key?(:id)
      params[:id]
    end
    return [] unless dicnames.present?

    dictionaries = dicnames.split(',').collect{|d| Dictionary.find_by_name(d.strip)}
    raise ArgumentError, "wrong dictionary specification." if dictionaries.include? nil

    dictionaries
  end

  def self.find_ids_by_labels(labels, dictionaries = [], threshold = 0.85, rich = false)
    ssdbs = dictionaries.inject({}) do |h, dic|
      h[dic.name] = begin
        Simstring::Reader.new(dic.ssdb_path)
      rescue
        nil
      end
      if h[dic.name]
        h[dic.name].measure = Simstring::Jaccard
        h[dic.name].threshold = threshold
      end
      h
    end

    r = labels.inject({}) do |h, label|
      h[label] = Entry.search_term(dictionaries, ssdbs, threshold, label)
      h[label].map!{|entry| entry[:identifier]} unless rich
      h
    end

    ssdbs.each{|name, db| db.close if db}

    r
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

  def tmp_ssdb_path
    Rails.root.join(ssdb_dir, "tmp_entries.db").to_s
  end

  def compile
    FileUtils.mkdir_p(ssdb_dir) unless Dir.exist?(ssdb_dir)
    # Simstring::Writer.new(db_filename, n-gram, begin/end marker, unicode)
    db = Simstring::Writer.new ssdb_path, 3, false, true

    # dictionary.entries.each do |entry|     # This is too slow.
    self.entries.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    # Entry.where(dictionary_id: self.id).pluck(:norm2).uniq.each {|norm2| db.insert norm2}

    Entry.delete(Entry.where(dictionary_id: self.id, mode:Entry::MODE_DELETION).pluck(:id))
    entries.where(mode:Entry::MODE_ADDITION).update_all(mode:Entry::MODE_NORMAL)

    db.close
  end

  def compiled_at
    File.mtime(ssdb_path).utc if ssdb_exist?
  end

  def compilable?
    num_addition > 0 || num_deletion > 0
  end
end
