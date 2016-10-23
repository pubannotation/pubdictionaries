class CreateEntries < ActiveRecord::Migration
  def change
    create_table :entries do |t|
      t.integer :mode, default: 0  # 1: addition, 2: deletion
      t.string :label
      t.string :norm1
      t.string :norm2
      t.integer :label_length
      t.string :identifier
      t.references :dictionary
      t.timestamps
    end

    add_index :entries, :label
    add_index :entries, :norm1
    add_index :entries, :label_length
    add_index :entries, :identifier
    add_index :entries, :mode
  end
end
