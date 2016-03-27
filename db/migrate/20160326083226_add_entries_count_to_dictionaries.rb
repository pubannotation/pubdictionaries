class AddEntriesCountToDictionaries < ActiveRecord::Migration
  def change
  	change_table :dictionaries do |t|
  		t.integer :entries_count, default: 0
  	end
  end
end
