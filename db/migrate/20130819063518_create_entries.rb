class CreateEntries < ActiveRecord::Migration
  def change
    create_table :entries do |t|
      t.string :label
      t.string :norm
      t.integer :norm_length
      t.integer :length_factor
      t.string :identifier
      t.boolean :flag, default: false
      t.timestamps
    end

		add_index :entries, :flag
    add_index :entries, :label
    add_index :entries, :identifier
  end
end
