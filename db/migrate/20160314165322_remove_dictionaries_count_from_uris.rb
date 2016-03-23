class RemoveDictionariesCountFromUris < ActiveRecord::Migration
  def up
  	change_table :uris do |t|
  		t.remove :dictionaries_count
  		t.rename :resource, :value
  	end
  end

  def down
  	change_table :uris do |t|
  		t.integer :dictionaries_count
  		t.rename  :value, :resource
  	end
  end
end
