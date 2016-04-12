class Dictionary < ActiveRecord::Base
  include StringManipulator

  attr_accessor :file, :separator, :sort
  attr_accessible :title, :creator, :description, :lowercased, :stemmed, :hyphen_replaced,
    :user_id, :public, :file, :separator, :sort, :language

  attr_accessible :active
  attr_accessible :issues

  belongs_to :user

  has_and_belongs_to_many :entries,
    :after_add => :entry_dictionaries_count_up,
    :after_remove => :entry_dictionaries_count_down

  has_many :labels, :through => :entries
  has_many :identifiers, :through => :entries
  has_many :jobs, :dependent => :destroy

  # validates :creator, :description, :title, :presence => true
  # validates :file, presence: true,  on: :create 
  validates :user_id, presence: true 
  validates :title, uniqueness: true
  validates_inclusion_of :public, :in => [true, false]     # :presence fails when the value is false.
  validates_format_of :title,                              # because of to_param overriding.
                      :with => /^[^\.]*$/,
                      :message => "should not contain dot!"

  def entry_dictionaries_count_up(entry)
    entry.dictionaries_count_up
  end

  def entry_dictionaries_count_down(entry)
    entry.dictionaries_count_down
  end

  def to_param
    # Override the original to_param so that it returns title, not ID, for constructing URLs. 
    # Use Model#find_by_title() instead of Model.find() in controllers.
    title
  end

  scope :active, where(active: true)

  scope :accessible, -> (user) {
    if user.nil?
      where('public = ?', true)
    else
      where('public = ? OR user_id = ?', true, user.id)
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

  def empty_entries
    entries.delete_all
    update_attribute(:entries_count, 0)
  end

  def self.find_labels_ids(labels, dictionaries = [], threshold = 0.8, rich = false)
    labels.inject({}) do |dic, label|
      dic[label] = find_label_ids(label, dictionaries, threshold, rich)[:ids]
      dic
    end
  end

  def self.find_label_ids(label, dictionaries = [], threshold = 0.8, rich = false)
    r = Label.find_similar_labels(label, Label.tokenize(label).collect{|t| t[:token]}, dictionaries, threshold, true)
    ids = r[:labels].inject([]) do |s, l|
      ids = get_ids(l[:id], dictionaries)
      s + ids.collect{|id| l.merge(id:id)}
    end
    ids.collect!{|id| id[:id]} unless rich
    {es_results: r[:es_results], ids: ids}
  end

  def self.get_ids_from_es_results(es_results, dictionaries)
    ids = es_results.inject([]){|s, r| s + self.get_ids(r.id, dictionaries).uniq.collect{|i| {label:r.value, identifier:i}}}
  end

  def self.get_ids(label_id, dictionaries = [])
    Identifier.joins(:entries).where("entries.label_id" => label_id).joins(:dictionaries).where("dictionaries.id" => dictionaries).pluck(:value)
  end

  def self.find_labels(ids, dictionaries = [])
  end

end

