class AddPublicToDictionary < ActiveRecord::Migration[5.2]
  def change
    add_column :dictionaries, :public, :boolean, default:false
  end
end
