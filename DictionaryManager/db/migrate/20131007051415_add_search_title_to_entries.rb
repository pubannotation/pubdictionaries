class AddSearchTitleToEntries < ActiveRecord::Migration
  def change
  	add_column :entries, :search_title, :string
  	add_column :new_entries, :search_title, :string
  end

  def down

  end
end
