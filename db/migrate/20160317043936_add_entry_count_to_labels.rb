class AddEntryCountToLabels < ActiveRecord::Migration
  def change
		add_column :labels, :entries_count, :integer, default: 0
  end
end
