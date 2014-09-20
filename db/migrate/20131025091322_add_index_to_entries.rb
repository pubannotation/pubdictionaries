class AddIndexToEntries < ActiveRecord::Migration
  def change
  	add_index :entries, :view_title
  end
end
