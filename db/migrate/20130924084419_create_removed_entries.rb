class CreateRemovedEntries < ActiveRecord::Migration
  def change
    create_table :removed_entries do |t|
      t.integer :user_dictionary_id
      t.integer :entry_id

      t.timestamps
    end
  end
end
