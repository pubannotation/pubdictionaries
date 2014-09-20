class UserDictionary < ActiveRecord::Base
  attr_accessor :sort
  attr_accessible :dictionary_id, :user_id, :sort

  belongs_to :user
  belongs_to :dictionary

  has_many :new_entries, dependent: :destroy
  has_many :removed_entries, dependent: :destroy

  validates :dictionary_id, :user_id, presence: true
  
  # Sort option constants.
  SORT_BY = [ [ "Entity name (asc)",   "view_title asc" ], 
              [ "Entity name (desc)",  "view_title desc" ],
              [ "Label (asc)",         "label asc" ], 
              [ "Label (desc)",        "label desc" ],
              [ "ID (asc)",            "uri asc" ], 
              [ "ID (desc)",           "uri desc" ],
            ]

  def search_new_entries(query, order="view_title asc", page)
    if order.nil? or order == ""
      order = "view_title asc"
    end

    if query
      new_entries.paginate :per_page => 15, 
                           :page => page,
                           # ILIKE is not a standard SQL, its PostgreSQL's extension.
                           :conditions => ["view_title ILIKE ? or label ILIKE ? or uri ILIKE ?", "%#{query}%", "%#{query}%", "%#{query}%"],
                           :order => order
    else
      new_entries.paginate :per_page => 15, :page => page, :order => order
    end
  end

  # Return a user dictionary associated with the user_id and the base dictionary.
  def self.get_or_create_user_dictionary(dictionary, current_user)
    user_dictionary = where({ user_id: current_user.id, dictionary_id: dictionary.id }).first
    if user_dictionary.nil?
      user_dictionary = new({ user_id: current_user.id, dictionary_id: dictionary.id })
      user_dictionary.save
    end
    user_dictionary
  end

  # Get a list of dictionaries that the user is working on.
  def self.get_dictionary_ids_by_user_id(user_id)
    select('distinct(dictionary_id)').where(user_id: user_id).collect do |ud|
      ud.dictionary_id
    end
  end

  def self.get_user_dictionaries_by_owner(base_dic)
    base_dic_id = Dictionary.find_by_title(base_dic).id
    where(dictionary_id: base_dic_id)
  end
 
end



