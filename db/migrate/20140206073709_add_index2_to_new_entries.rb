class AddIndex2ToNewEntries < ActiveRecord::Migration
  def change
  	add_index :new_entries, :label
  	add_index :new_entries, :uri
  end
end
