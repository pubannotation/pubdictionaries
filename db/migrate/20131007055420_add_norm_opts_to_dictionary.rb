class AddNormOptsToDictionary < ActiveRecord::Migration
  def change
  	add_column :dictionaries, :lowercased, :bool
  	add_column :dictionaries, :stemmed, :bool
  	add_column :dictionaries, :hyphen_replaced, :bool
  end
end
