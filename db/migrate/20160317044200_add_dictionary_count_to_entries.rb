class AddDictionaryCountToEntries < ActiveRecord::Migration
  def change
		add_column :entries, :dictionaries_count, :integer, default: 0
  end
end
