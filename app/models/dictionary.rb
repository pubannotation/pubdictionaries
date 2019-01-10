require 'simstring'

class Dictionary < ActiveRecord::Base
  include StringManipulator

  belongs_to :user
  has_many :associations
  has_many :associated_managers, through: :associations, source: :user
  has_many :dl_associations
  has_many :languages, through: :dl_associations, source: :language
  has_many :entries, :dependent => :destroy
  has_many :jobs, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true 
  validates :description, presence: true
  validates :license_url, url: {allow_blank: true}
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /^[^\.]*$/,
                      :message => "should not contain dot!"

  SIM_STRING_DB_DIR = "db/simstring/"

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

  scope :administrable, -> (user) {
    if user.nil?
      none
    elsif user.admin?
    else
      where('user_id = ?', user.id)
    end
  }

  class << self
    def find_dictionaries_from_params(params)
      dic_names = if params.has_key?(:dictionaries)
                   params[:dictionaries]
                 elsif params.has_key?(:dictionary)
                   params[:dictionary]
                 elsif params.has_key?(:id)
                   params[:id]
                 end
      return [] unless dic_names.present?

      dictionaries = dic_names.split(',').collect{|d| Dictionary.find_by_name(d.strip)}
      raise ArgumentError, "wrong dictionary specification." if dictionaries.include? nil

      dictionaries
    end

    def find_ids_by_labels(labels, dictionaries = [], threshold = 0.85, rich = false)
    sim_string_dbs = dictionaries.inject({}) do |h, dic|
      h[dic.name] = begin
        Simstring::Reader.new(dic.sim_string_db_path)
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
      h[label] = Entry.search_term(dictionaries, sim_string_dbs, threshold, label)
      h[label].map!{|entry| entry[:identifier]} unless rich
      h
    end

    sim_string_dbs.each{|name, db| db.close if db}

    r
    end
  end

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  def editable?(user)
    user && (user.admin? || user_id == user.id || associated_managers.include?(user))
  end

  def administrable?(user)
    user && (user.admin? || user_id == user.id)
  end

  def create_addition(label, id)
    increment!(:entries_num) if create_addition_entry(id, label)
    update_tmp_sim_string_db
  end

  def create_deletion(entry)
    entry.be_deletion!
    decrement!(:entries_num)
  end

  def undo_entry(entry)
    if entry.addition?
      entry.delete
      decrement!(:entries_num)
    elsif entry.deletion?
      entry.be_normal!
      increment!(:entries_num)
    end

    update_tmp_sim_string_db
  end

  def num_addition
    entries.where(mode:Entry::MODE_ADDITION).count
  end

  def num_deletion
    entries.where(mode:Entry::MODE_DELETION).count
  end

  def add_entries(pairs, normalizer = nil)
    transaction do
      new_entries = pairs.map {|label, id| Entry.new_for(self.id, label, id, normalizer)}

      r = Entry.import new_entries, validate: false
      raise "Import error" unless r.failed_instances.empty?

      increment!(:entries_num, new_entries.length)
    end
  end

  def empty_entries
    transaction do
      # Generate to one delete SQL statement for performance
      Entry.delete(Entry.where(dictionary_id: self.id).pluck(:id))
      update_attribute(:entries_num, 0)
    end
  end

  def sim_string_db_path
    Rails.root.join(sim_string_db_dir, "simstring.db").to_s
  end

  def tmp_sim_string_db_path
    Rails.root.join(sim_string_db_dir, "tmp_entries.db").to_s
  end

  def compile
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new sim_string_db_path, 3, false, true

    entries
      .where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION])
      .pluck(:norm2)
      .uniq
      .each{|norm2| db.insert norm2}

    # Generate to one delete SQL statement for performance
    Entry.delete(Entry.where(dictionary_id: self.id, mode:Entry::MODE_DELETION).pluck(:id))
    entries.where(mode:Entry::MODE_ADDITION).update_all(mode: Entry::MODE_NORMAL)

    db.close
  end

  def compilable?
    num_addition > 0 || num_deletion > 0
  end

  private

  def create_addition_entry(id, label)
    e = entries.find_by_label_and_identifier(label, id)
    return unless e.nil?

    params = Entry.addition_entry_params(label, id)
    entries.create(params)
    true
  end

  def sim_string_db_dir
    Dictionary::SIM_STRING_DB_DIR + self.name
  end

  def update_tmp_sim_string_db
    FileUtils.mkdir_p(sim_string_db_dir) unless Dir.exist?(sim_string_db_dir)
    db = Simstring::Writer.new tmp_sim_string_db_path, 3, false, true
    self.entries.where(mode: [Entry::MODE_NORMAL, Entry::MODE_ADDITION]).pluck(:norm2).uniq.each{|norm2| db.insert norm2}
    db.close
  end
end
