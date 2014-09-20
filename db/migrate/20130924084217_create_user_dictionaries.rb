class CreateUserDictionaries < ActiveRecord::Migration
  def change
    create_table :user_dictionaries do |t|
      t.integer :user_id
      t.integer :dictionary_id

      t.timestamps
    end
  end
end
