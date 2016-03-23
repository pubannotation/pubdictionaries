#
# Define the Dictionary model.
#
class Dictionary < ActiveRecord::Base
  include StringManipulator

  attr_accessor :file, :separator, :sort
  attr_accessible :title, :creator, :description, :lowercased, :stemmed, :hyphen_replaced,
    :user_id, :public, :file, :separator, :sort, :language

  attr_accessible :ready
  attr_accessible :issues

  belongs_to :user

  has_and_belongs_to_many :entries,
    :after_add => :entry_dictionaries_count_up,
    :after_remove => :entry_dictionaries_count_down

  has_many :labels, :through => :entries
  has_many :uris, :through => :entries

  has_many :user_dictionaries, :dependent => :destroy

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

  # Return a list of dictionaries.
  def self.get_showables(user = nil, dic_type = nil)
    if user == nil
      # Get a list of publicly available dictionaries.
      lst = where('public = ? AND ready = ?', true, true)
      order = 'created_at'
      order_direction = 'desc'

    else
      if dic_type == 'my_dic'
        # Get a list of dictionaries of the current user.
        lst = where('user_id = ?', user.id)
        order = 'created_at'
        order_direction = 'desc'

      elsif dic_type == 'working_dic'
        dic_ids = UserDictionary.get_dictionary_ids_by_user_id(user.id)

        # Get a list of working dictionaries. Dictionaries, which are not confirmed, will
        #   be shown if those are created by the current user, whereas only confirmed 
        #   dictionaries will be shown if they are created by other users.
        lst = Dictionary.joins(:user_dictionaries).
                where('dictionaries.id IN (?)', dic_ids).
                where('(dictionaries.user_id = ? AND ready = ?)
                  OR (dictionaries.user_id != ? AND ready = ?)',
                  user.id, true, user.id, true)
        order = 'user_dictionaries.updated_at'
        order_direction = 'desc'

      else
        # Get a list of all dictionaries.
        lst = where('(user_id != ? AND public = ? AND ready = ?) OR (user_id = ?)',
                user.id, true, true, user.id)
        order = 'created_at'
        order_direction = 'desc'
      end
    end

    return lst, order, order_direction
  end


  # Find a dictionary by its title.
  # @return
  #   dictionary instance - a dictionary foundnil - 'title' dictionary does not 
  #   exist or not showable. nil if it does not exist or showable dictionary by its title.
  def self.find_showable_by_title(title, user = nil)
    if user.nil?
      where(:title => title).where('public = ?', true).where(:ready => true).first
    else
      where(:title => title).where('public = ? OR user_id = ?', true, user.id).where(:ready => true).first
    end
  end


  # Return a list of latest showable dictionaries.
  def self.get_latest_dictionaries(n=10)
    where('public = ? AND ready = ?', true, true).order('created_at desc').limit(n)
  end

  # Get a list of unfinished work.
  def self.get_unfinished_dictionaries(user)
    where(user_id: user.id).where(ready: false)
  end

  def unfinished?
    ready == false
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

  def cleanup
  end

  # Refactored as a method for delayed_job
  def load_from_file(file, separator = "\t")
    # Note: "textmode: true" option automatically converts all newline variants to \n
    # fp = File.open(file, textmode: true)

    begin
      ActiveRecord::Base.transaction do
        File.foreach(file).with_index do |line, line_no|
          label, uri = parse_entry_line(line, separator, line_no)
          self.entries << Entry.get_by_value(label, uri) unless label.nil?
        end
        update_attribute(:ready, true)
      end
    # rescue => e
      # self.cleanup
    end

    # File.delete(file)

    Delayed::Job.enqueue(DelayedRake.new("elasticsearch:import:model", class: 'Label', scope: "diff"))
    Delayed::Job.enqueue(DelayedRake.new("elasticsearch:import:model", class: 'Uri', scope: "diff"))
  end

  def parse_entry_line(line, sep, line_no)
    line.strip!

    if line == ''
      # Silently ignore blank lines.
      return nil
    end

    # Field-wise check.
    items = line.split sep

    if items.size < 2
      self.issues += "#{line_no}-th line has #{items.size} field(s).\n"
      return nil
    end

    items.each do |item|
      if item.length > 255
        self.issues += "#{line_no}-th line has a field that is longer than 255!\n"
        return nil
      end
    end

    return items
  end

  def remove
    
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

