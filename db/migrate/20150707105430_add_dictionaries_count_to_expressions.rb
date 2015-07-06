class AddDictionariesCountToExpressions < ActiveRecord::Migration
  def change
  	add_column :expressions, :dictionaries_count, :integer, default: 0
  end
end
