class RemoveDelayedJobIdColumnToJobs < ActiveRecord::Migration[6.1]
  def up
    remove_column :jobs, :delayed_job_id, :bigint
  end

  def down
    add_column :jobs, :delayed_job_id, :bigint
    add_index :jobs, :delayed_job_id
  end
end
