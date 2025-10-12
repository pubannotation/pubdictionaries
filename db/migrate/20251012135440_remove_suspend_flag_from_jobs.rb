class RemoveSuspendFlagFromJobs < ActiveRecord::Migration[8.0]
  def change
    remove_column :jobs, :suspend_flag, :boolean, default: false
  end
end
