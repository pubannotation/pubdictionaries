class ChangeColumnTypeFromStringToText < ActiveRecord::Migration
  def up
  	change_column :entries, :view_title, :text
  	change_column :entries, :search_title, :text
  	change_column :entries, :label, :text

  	change_column :new_entries, :view_title, :text
  	change_column :new_entries, :search_title, :text
  	change_column :new_entries, :label, :text
  	change_column :new_entries, :uri, :text
  end

  def down
  	change_column :entries, :view_title, :string
  	change_column :entries, :search_title, :string
  	change_column :entries, :label, :string

  	change_column :new_entries, :view_title, :string
  	change_column :new_entries, :search_title, :string
  	change_column :new_entries, :label, :string
  	change_column :new_entries, :uri, :string
  end
end
