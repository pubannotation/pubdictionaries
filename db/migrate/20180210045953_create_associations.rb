class CreateAssociations < ActiveRecord::Migration
  def change
    create_table :associations do |t|
      t.references :user
      t.references :dictionary

      t.timestamps
    end
    add_index :associations, :user_id
    add_index :associations, :dictionary_id
  end
end
