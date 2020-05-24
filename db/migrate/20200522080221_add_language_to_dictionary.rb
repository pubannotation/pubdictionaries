class AddLanguageToDictionary < ActiveRecord::Migration[5.2]
  def change
    add_column :dictionaries, :language, :string
  end
end
