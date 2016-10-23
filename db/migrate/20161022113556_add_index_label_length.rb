class AddIndexLabelLength < ActiveRecord::Migration
	def up
		add_index :entries, :label_length
	end

  def down
		remove_index :entries, :label_length
  end
end
