class AddEntryCountToUris < ActiveRecord::Migration
  def change
		add_column :uris, :entries_count, :integer, default: 0
  end
end
