class AddDirtyToEntries < ActiveRecord::Migration[5.2]
	def up
		add_column :entries, :dirty, :boolean, default: false
		execute "UPDATE entries SET dirty = true WHERE mode = 1"
		add_index :entries, :dirty
	end

	def down
		remove_index :entries, :dirty
		remove_column :entries, :dirty
	end
end
