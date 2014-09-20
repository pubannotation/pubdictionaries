class AddIndexToNewEntries < ActiveRecord::Migration
  def change
  	add_index :new_entries, :view_title
  	add_index :new_entries, :user_dictionary_id
  end
end
