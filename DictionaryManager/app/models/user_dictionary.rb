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
end
