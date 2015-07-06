class AddDictionariesCountToUris < ActiveRecord::Migration
  def change
  	add_column :uris, :dictionaries_count, :integer, default: 0
  end
end
