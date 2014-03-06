#
# Define the Dictionary model.
#

class Dictionary < ActiveRecord::Base

  attr_accessor :file, :separator, :sort
  attr_accessible :title, :creator, :description, :lowercased, :stemmed, :hyphen_replaced, :user_id, :public, :file, :separator, :sort

  belongs_to :user

  has_many :entries, :dependent => :destroy
  has_many :user_dictionaries, :dependent => :destroy

  validates :creator, :description, :title, :presence => true
  validates :title, uniqueness: true
  validates_inclusion_of :public, :in => [true, false]     # :presence fails when the value is false.
  validates_format_of :title,                              # because of to_param overriding.
                      :with => /^[^\.]*$/,
                      :message => "should not contain dot!"

  
  # Overrides original to_param so that it returns title, not ID, for constructing URLs. 
  # Use Model#find_by_title() instead of Model.find() in controllers.
  def to_param
    title
  end

  # Return a list of dictionaries.
  def self.get_showables(user=nil, dic_type=nil)
    if user == nil
      lst   = where(:public => true)
      order = 'created_at'
      order_direction = 'desc'

    else
      if dic_type == 'my_dic'
        lst   = where(user_id: user.id)
        order = 'created_at'
        order_direction = 'desc'

      elsif dic_type == 'working_dic'
        dic_ids = UserDictionary.get_dictionary_ids_by_user_id(user.id)

        # Sort a list based on user_dictionaries#updated_at attribute. 
        lst   = Dictionary.joins(:user_dictionaries).where('dictionaries.id IN (?)', dic_ids)
        order = 'user_dictionaries.updated_at'
        order_direction = 'desc'

      else
        lst   = where('public = ? OR user_id = ?', true, user.id)
        order = 'created_at'
        order_direction = 'desc'
      end
    end

    return lst, order, order_direction
  end

  # Find a dictionary by its title.
  # @return
  #   dictionary instance - a dictionary foundnil - 'title' dictionary does not exist or not showable.
  #    nil if it does not exist or showable dictionary by its title.
  def self.find_showable_by_title(title, user)
    if user.nil?
      where(title: title).where(public: true).first
    else
      where(title: title).where('public = ? OR user_id = ?', true, user.id).first
    end
  end

  # Return a list of latest showable dictionaries.
  def self.get_latest_dictionaries(n=10)
    where('public = ?', true).order('created_at desc').limit(n)
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


  private

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
