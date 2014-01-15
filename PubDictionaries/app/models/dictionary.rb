class Dictionary < ActiveRecord::Base
  # default_scope :order => 'title'

  attr_accessor :file, :separator, :sort
  attr_accessible :creator, :description, :title, :stemmed, :lowercased, :hyphen_replaced, :public, :file, :separator, :sort

  belongs_to :user

  has_many :entries, :dependent => :destroy
  has_many :user_dictionaries, :dependent => :destroy

  validates :creator, :description, :title, :presence => true
  validates :title, uniqueness: true
  validates_inclusion_of :public, :in => [true, false]     # :presence fails when the value is false.


  # Overrides original to_param so that it returns title, not ID, for constructing URLs. 
  # Use Model#find_by_title() instead of Model.find() in controllers.
  def to_param
    title
  end

  # Return a list of dictionaries that are either public or belonging to the logged in user.
  def self.get_showables(user)
    if user == nil
      Dictionary.where(:public => true)
    else
      Dictionary.where('public = ? OR user_id = ?', true, user.id)
    end
  end

  # 
  def self.find_showable_by_title(title, user_id)
    dic = Dictionary.find_by_title(title)
    if not dic.nil?
      if dic.public == true or (user_id == dic.user_id)
        return dic
      end
    end
    return nil
  end

  # true if the given base dictionary is destroyable; otherwise, false.
  def is_destroyable?(current_user)
    if self.user_id != current_user.id
      return false, "Current user is not the owner of the dictionary."
    elsif used_by_other_users?
      return false, "The dictionary is used by other users."
    else
      return true, "The dictionary is successfully deleted."
    end
  end


  private

  def used_by_other_users?
    self.user_dictionaries.each do |user_dic|
      if not user_dic.new_entries.where("user_dictionary_id = ?", user_dic.id).empty? or
         not user_dic.removed_entries.where("user_dictionary_id = ?", user_dic.id).empty?
        return true
      end
    end
    return false
  end

end
