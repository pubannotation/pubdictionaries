class AddIndexDictionaryToEntry < ActiveRecord::Migration
  def change
    add_index :entries, :dictionary_id
  end
end
