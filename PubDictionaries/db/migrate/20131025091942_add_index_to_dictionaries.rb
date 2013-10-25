class AddIndexToDictionaries < ActiveRecord::Migration
  def change
  	add_index :dictionaries, :title
  	add_index :dictionaries, :creator
  end
end
