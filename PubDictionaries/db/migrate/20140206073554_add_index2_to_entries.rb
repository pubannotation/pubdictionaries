class AddIndex2ToEntries < ActiveRecord::Migration
  def change
  	add_index :entries, :label
  	add_index :entries, :uri
  end
end
