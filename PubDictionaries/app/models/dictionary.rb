#
# Define the Dictionary model.
#
require File.join( Rails.root, '..', 'simstring/swig/ruby/simstring')

class Dictionary < ActiveRecord::Base
  include StringManipulator


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

  
  def to_param
    # Override the original to_param so that it returns title, not ID, for constructing URLs. 
    # Use Model#find_by_title() instead of Model.find() in controllers.
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
  #   dictionary instance - a dictionary foundnil - 'title' dictionary does not 
  #   exist or not showable. nil if it does not exist or showable dictionary by its title.
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


  # Refactored as a method for delayed_job
  def import_entries_and_create_simstring_db(file, separator)
    # 1. Import entries.
    if import_entries(file, separator) == false
      return false
    end
    
    # 2. Create a SimString DB.
    if create_ssdb == false
      delete_ssdb
      return false
    end

    File.delete file

    return true
  end

  # Clean-up entries, user_dictionaries, and simstring db in a fast way.
  def destroy_entries_and_simstring_db
    # 1. Delete the entries of a base dictionary.
    #    - Use "delete_all" instead of "destroy" to speed up.
    #
    # self.entries.delete_all  # Caution!!!  This will delete each entry at a time!!
    Entry.delete_all  ["dictionary_id = ?", self.id]

    # 2. Delete user dictionaries associated with the base dictionary, 
    #   and their entries.
    self.user_dictionaries.each do |user_dic|
      # user_dic.new_entries.delete_all
      # user_dic.removed_entries.delete_all
      NewEntry.delete_all  ["user_dictionary_id = ?", user_dic.id]
      RemovedEntry.delete_all  ["user_dictionary_id = ?", user_dic.id]

      user_dic.destroy
    end

    # 3. Delete the associated SimString DB.
    delete_ssdb

    return true
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


  ########################################################
  #####     Codes for creating a new dictionary.     #####
  ########################################################

  # Import entries.
  def import_entries(file, separator)
    if file.nil?
      return false
    else
      fp = File.open(file)
      while (tmp_entries = read_entries(fp, separator, 1000)) != [] do
        self.entries.import tmp_entries
      end
      fp.close()
      return true
    end
  end

  def read_entries(fp, separator, max_entries)
    new_entries = []

    (0...max_entries).each do |n|
      if fp.eof?
        $stderr.puts "-- 3"
        break
      else
        $stderr.puts "-- 4"
        line  = fp.readline.strip!
        items = line.split separator
    
        # Create an array of entries.
        e = Entry.new( 
          { view_title:   items[0], 
            search_title: normalize_str(
              items[0], 
              { lowercased: self.lowercased, 
                hyphen_replaced: self.hyphen_replaced, 
                stemmed: self.stemmed,
              } ), 
            uri:          items[1],
            label:        items[2],     # nil if label column is not given.
          } )
        $stderr.puts "-- 5"
        e.dictionary_id = self.id
        new_entries << e
        $stderr.puts "-- 6"
      end
    end

    return new_entries
  end

  # Create a SimString DB.
  def create_ssdb
    dbfile_path = Rails.root.join('public/simstring_dbs', self.title).to_s

    begin
      # Simstring::Writer.new(db_filename, n-gram, begin/end marker, unicode)
      db = Simstring::Writer.new  dbfile_path, 3, true, true     
    rescue => e
      logger.error "Failed to create a SimString DB: #{e}"
      return false
    end
    
    # @dictionary.entries.each do |entry|     # This is too slow. 
    # Entry.where(dictionary_id: @dictionary.id).pluck(:search_title).uniq.each do |search_title|
    self.entries.pluck(:search_title).uniq.each do |search_title|
      db.insert  search_title
    end

    db.close

    return true
  end
  

  ######################################################
  #####     Codes for destroying a dictionary.     #####
  ######################################################

  def delete_ssdb
    dbfile_path = Rails.root.join('public/simstring_dbs', self.title).to_s
    
    # Remove the main db file
    begin
      File.delete  dbfile_path
    rescue => e
      Rails.logger.debug "Failed to delete a simstring DB: #{e}"
    end

    # Remove auxiliary db files
    pattern = dbfile_path + ".[0-9]+.cdb"
    Dir.glob(dbfile_path + '.*.cdb').each do |aux_file|
      if /#{pattern}/.match(aux_file) 
        begin
          File.delete  aux_file
        rescue
          # Silently ignore the error
        end
      end
    end
  end

 
end

