class AddUserIdToDictionary < ActiveRecord::Migration
  def change
    add_column :dictionaries, :user_id, :integer
  end
end
