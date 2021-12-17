class AddSuspendFlagToJob < ActiveRecord::Migration[6.1]
  def change
    add_column :jobs, :suspend_flag, :boolean, default: false
  end
end
