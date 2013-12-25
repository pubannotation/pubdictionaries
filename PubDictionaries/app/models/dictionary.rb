class Dictionary < ActiveRecord::Base
  # default_scope :order => 'title'

  attr_accessor :file, :separator, :sort
  attr_accessible :creator, :description, :title, :file, :stemmed, :lowercased, :hyphen_replaced, :separator, :sort

  belongs_to :user

  has_many :entries, :dependent => :destroy
  has_many :user_dictionaries, :dependent => :destroy

  validates :creator, :description, :title, :presence => true
  validates :title, uniqueness: true

  # Sets the constant values of the sort option.
  SORT_BY = [ [ "Entity name (asc)",   "view_title asc" ], 
              [ "Entity name (desc)",  "view_title desc" ],
              [ "Label (asc)",         "label asc" ], 
              [ "Label (desc)",        "label desc" ],
              [ "ID (asc)",            "uri asc" ], 
              [ "ID (desc)",           "uri desc" ],
            ]

  # Supports search func.
  def search_entries(query, order, page)
    if order.nil? or order == ""
      order = "view_title asc"
    end

    if query
      # :order does not work probably due to default scope. Use reorder to force it.
      # ILIKE is not a standard SQL, its PostgreSQL's extension.
      entries.paginate(:per_page => 15, :page => page, :conditions => 
        ["view_title ILIKE ? or label ILIKE ? or uri ILIKE ?", "%#{query}%", "%#{query}%", "%#{query}%"])
        .reorder(order)
    else
      entries.paginate(:per_page => 15, :page => page).reorder(order)
    end
  end

  # Overrides original to_param so that it returns title, not ID, for
  #   constructing URLs. Use Model#find_by_title() instead of 
  #   Model.find() in controllers.
  def to_param
    title
  end

end
