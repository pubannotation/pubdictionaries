class AddLanguageToDictionaries < ActiveRecord::Migration
  def change
  	add_column :dictionaries, :language, :string
  end
end
