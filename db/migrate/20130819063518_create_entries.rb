class CreateEntries < ActiveRecord::Migration
  def change
    create_table :entries do |t|
      t.string :label
      t.string :norm1
      t.string :norm2
      t.integer :label_length
      t.integer :norm1_length
      t.integer :norm2_length
      t.string :identifier
      t.boolean :flag, default: false
      t.timestamps
    end

		add_index :entries, :flag
    add_index :entries, :label
    add_index :entries, :identifier
  end
end
