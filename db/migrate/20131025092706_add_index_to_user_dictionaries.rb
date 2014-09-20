class AddIndexToUserDictionaries < ActiveRecord::Migration
  def change
  	add_index :user_dictionaries, :user_id
  	add_index :user_dictionaries, :dictionary_id
  end
end
