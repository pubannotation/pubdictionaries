class AddPublicToDictionary < ActiveRecord::Migration
  def change
    add_column :dictionaries, :public, :boolean, default:false
  end
end
