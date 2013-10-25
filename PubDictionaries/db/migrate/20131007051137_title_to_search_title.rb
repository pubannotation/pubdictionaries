class TitleToSearchTitle < ActiveRecord::Migration
  def up
  	change_table :entries do |t|
  		t.rename :title, :view_title
  	end  	
  	change_table :new_entries do |t|
  		t.rename :title, :view_title
  	end  	
  end

  def down
  	change_table :entries do |t|
  		t.rename :view_title, :title
  	end  	
  	change_table :new_entries do |t|
  		t.rename :view_title, :title
  	end  	

  end
end
