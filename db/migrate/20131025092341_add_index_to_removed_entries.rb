class AddIndexToRemovedEntries < ActiveRecord::Migration
  def change
  	add_index :removed_entries, :user_dictionary_id
  	add_index :removed_entries, :entry_id
  end
end
