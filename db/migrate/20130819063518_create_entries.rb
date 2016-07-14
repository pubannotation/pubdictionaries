class CreateEntries < ActiveRecord::Migration
  def change
    create_table :entries do |t|
      t.string :label
      t.string :terms
      t.integer :terms_length
      t.string :identifier
      t.boolean :flag, default: false
      t.timestamps
    end

		add_index :entries, :flag
    add_index :entries, :label
    add_index :entries, :identifier
  end
end
