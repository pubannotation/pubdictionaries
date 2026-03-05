class ReplaceAdminWithUserLevel < ActiveRecord::Migration[7.0]
  def up
    add_column :users, :user_level, :integer, default: 0, null: false
    User.where(admin: true).update_all(user_level: 9)
    remove_column :users, :admin
  end

  def down
    add_column :users, :admin, :boolean, default: false
    User.where("user_level >= 9").update_all(admin: true)
    remove_column :users, :user_level
  end
end
