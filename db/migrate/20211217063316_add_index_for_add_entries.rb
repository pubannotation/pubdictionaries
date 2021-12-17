class AddIndexForAddEntries < ActiveRecord::Migration[6.1]
	def change
		add_index :entries, [:dictionary_id, :label, :identifier]
	end
end
