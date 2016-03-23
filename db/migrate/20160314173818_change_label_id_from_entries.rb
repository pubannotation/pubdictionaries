class ChangeLabelIdFromEntries < ActiveRecord::Migration
  def up
  	change_table :entries do |t|
	  	t.remove :view_title
	  	t.remove :search_title
	  	t.remove :label
	  	t.remove :uri
	  	t.remove :dictionary_id
	  	t.references :label
	  	t.references :uri
	  end
  end

  def down
  	change_table :entries do |t|
	  	t.string :view_title
	  	t.string :search_title
	  	t.string :label
	  	t.string :uri
	  	t.references :dictionary
	  	t.remove :label_id
	  	t.remove :uri_id
	  end
	end
end
