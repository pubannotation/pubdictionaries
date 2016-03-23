class AddStatusToDictionaries < ActiveRecord::Migration
  def up
  	change_table :dictionaries do |t|
  		t.remove :uploaded
  		t.remove :confirmed
  		t.boolean :ready, :default => true
  	end
  end

  def down
  	change_table :dictionaries do |t|
  		t.boolean :uploaded, :default => false
  		t.boolean :confirmed, :default => false
   		t.remove  :ready
  	end
  end
end
