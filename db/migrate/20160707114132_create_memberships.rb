class CreateMemberships < ActiveRecord::Migration
  def change
    create_table :memberships do |t|
      t.references :dictionary
      t.references :entry
      t.timestamps
    end

    add_index :memberships, :dictionary_id
    add_index :memberships, :entry_id

    change_table :dictionaries do |t|
    	t.integer :entries_num, default: 0
    end

    change_table :entries do |t|
    	t.integer :dictionaries_num, default: 0
    end
  end
end
