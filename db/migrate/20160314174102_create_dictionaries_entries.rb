class CreateDictionariesEntries < ActiveRecord::Migration
  def up
    create_table :dictionaries_entries, :id => false do |t|
        t.references :dictionary
        t.references :entry
    end
    add_index :dictionaries_entries, [:dictionary_id, :entry_id]
  end

  def down
  	drop_table :dictionaries_entries
  end
end
