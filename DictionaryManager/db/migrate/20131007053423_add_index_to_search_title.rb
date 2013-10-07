class AddIndexToSearchTitle < ActiveRecord::Migration
  def change
  	add_index :entries, :search_title
	add_index :new_entries, :search_title
  end
end
