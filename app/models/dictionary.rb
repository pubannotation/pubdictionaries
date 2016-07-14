class Dictionary < ActiveRecord::Base
  include StringManipulator

  attr_accessible :name, :description, :user_id, :language
  attr_accessible :active
  attr_accessible :entries_num

  belongs_to :user

  has_many :membership
  has_many :entries, :through => :membership

  has_many :jobs, :dependent => :destroy

  validates :name, presence:true, uniqueness: true
  validates :user_id, presence: true 
  validates :description, presence: true
  validates_format_of :name,                              # because of to_param overriding.
                      :with => /^[^\.]*$/,
                      :message => "should not contain dot!"

  # Override the original to_param so that it returns name, not ID, for constructing URLs.
  # Use Model#find_by_name() instead of Model.find() in controllers.
  def to_param
    name
  end

  scope :active, where(active: true)

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
    label = Entry.uncapitalize(label)

    e = Entry.get_by_value(label, id)
    if e.nil?
      terms = Entry.tokenize(label).collect{|t| t[:token]}
      e = Entry.create(label:label, identifier:id, terms: terms.join("\t"), terms_length: terms.length)
    end

    unless entries.include?(e)
      entries << e
      increment!(:entries_num)
      e.increment!(:dictionaries_num)
      e.__elasticsearch__.index_document
    end
  end

  def destroy_entry(e)
    if entries.include?(e)
      entries.destroy(e)
      decrement!(:entries_num)
      e.decrement!(:dictionaries_num)

      if e.dictionaries_num == 0
        e.destroy
        e.__elasticsearch__.delete_document
      else
        e.__elasticsearch__.index_document
      end
    end
  end

  def add_new_entries(pairs)
    # ActiveRecord::Base.transaction do
      new_entries = pairs.map do |label, id|
        label = Entry.uncapitalize(label)
        terms = Entry.tokenize(label).collect{|t| t[:token]}
        Entry.new(label:label, identifier:id, terms: terms.join("\t"), terms_length: terms.length, dictionaries_num:1, flag:true)
      end
      r = Entry.import new_entries, validate: false
      raise "Import error" unless r.failed_instances.empty?

      self.entries += Entry.where(flag: true)
      Entry.__elasticsearch__.import query: -> {where(flag:true)}
      Entry.where(flag: true).update_all(flag: false)

      increment!(:entries_num, new_entries.length)
    # end
  end

  def add_entries(entries)
    # ActiveRecord::Base.transaction do
      self.entries += entries
      entries.update_all('dictionaries_num = dictionaries_num + 1')

      entries.update_all(flag:true)
      Entry.__elasticsearch__.import query: -> {where(flag:true)}
      entries.update_all(flag:false)

      increment!(:entries_num, entries.length)
    # end
  end

  def empty_entries
    entries.update_all('dictionaries_num = dictionaries_num - 1')
    Entry.delete(Entry.joins(:membership).where("memberships.dictionary_id" => self.id, dictionaries_num: 0).pluck(:id))

    entries.update_all(flag:true)
    entries.delete_all
    Entry.__elasticsearch__.import query: -> {where(flag:true)}
    Entry.where(flag:true).update_all(flag:false)

    update_attribute(:entries_num, 0)
  end

  def self.find_labels_ids(labels, dictionaries = [], threshold = 0.85, rich = false)
    labels.inject({}) do |dic, label|
      dic[label] = Entry.search_by_label(label, Label.tokenize(label).collect{|t| t[:token]}, dictionaries, threshold)[:entries]
      dic[label].map!{|entry| entry[:identifier]} unless rich
      dic
    end
  end
end
