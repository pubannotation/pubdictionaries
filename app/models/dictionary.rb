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

  def self.find_ids(labels, dictionaries = [], threshold = 0.65, rich = false)
    threshold ||= 0.65
    rich ||= false
    dic = {}
    labels.each do |label|
      mlabels = Label.search_as_term(label, dictionaries).records
      ids = mlabels.inject([]){|s, mlabel| s + mlabel.entries.collect{|e| {label:e.label.value, identifier:e.identifier.value}}}.uniq
      ids = ids.collect{|id| id.merge(score: Strsim.cosine(id[:label].downcase, label.downcase))}
      ids.delete_if{|id| id[:score] < threshold}
      ids = ids.collect{|id| id[:identifier]}.uniq unless rich
      dic[label] = ids
    end
    dic
  end

  def self.find_labels(ids, dictionaries = [])
  end

  # Return a list of dictionaries.
  def self.get_showables(user = nil, dic_type = nil)
    if user == nil
      # Get a list of publicly available dictionaries.
      lst = where('public = ? AND active = ?', true, true)
      order = 'created_at'
      order_direction = 'desc'

    else
      # Get a list of all dictionaries.
      lst = where('(user_id != ? AND public = ? AND active = ?) OR (user_id = ?)',
              user.id, true, true, user.id)
    end

    return lst, order, order_direction
  end


  # Find a dictionary by its title.
  # @return
  #   dictionary instance - a dictionary foundnil - 'title' dictionary does not 
  #   exist or not showable. nil if it does not exist or showable dictionary by its title.
  def self.find_showable_by_title(title, user = nil)
    if user.nil?
      where(:title => title).where('public = ?', true).where(:active => true).first
    else
      where(:title => title).where('public = ? OR user_id = ?', true, user.id).where(:active => true).first
    end
  end


  # Return a list of latest showable dictionaries.
  def self.get_latest_dictionaries(n=10)
    where('public = ? AND active = ?', true, true).order('created_at desc').limit(n)
  end

  # Get a list of unfinished work.
  def self.get_unfinished_dictionaries(user)
    where(user_id: user.id).where(active: false)
  end

  def unfinished?
    active == false
  end


  # true if the given base dictionary is destroyable; otherwise, false.
  def is_destroyable?(current_user)
    if self.user_id != current_user.id
      return false, "Current user is not the owner of the dictionary."
    elsif used_by_other_users?(current_user)
      return false, "The dictionary is used by other users."
    else
      return true, "The dictionary is successfully deleted."
    end
  end


  #######
  private
  #######

  # true if other users are using this base dictionary (new entries or disabled entries exist).
  def used_by_other_users?(current_user)
    self.user_dictionaries.each do |user_dic|
      if user_dic.user_id != current_user.id 
        if not user_dic.new_entries.empty? or not user_dic.removed_entries.empty?
          return true
        end
      end
    end
    return false
  end

end

