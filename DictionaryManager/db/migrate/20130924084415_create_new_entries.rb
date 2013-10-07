class CreateNewEntries < ActiveRecord::Migration
  def change
    create_table :new_entries do |t|
      t.string :title
      t.string :label
      t.string :uri
      t.integer :user_dictionary_id

      t.timestamps
    end
  end
end
