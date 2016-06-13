class ChangeTitleToNameFromDictionaries < ActiveRecord::Migration
  def change
  	change_table :dictionaries do |t|
  		t.rename :title, :name
  	end
  end
end
