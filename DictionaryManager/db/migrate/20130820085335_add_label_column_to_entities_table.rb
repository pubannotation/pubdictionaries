class AddLabelColumnToEntitiesTable < ActiveRecord::Migration
  def change
  	add_column :entries, :label, :string
  end

end
