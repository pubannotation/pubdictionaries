class AddColumnToJobs < ActiveRecord::Migration[6.1]
  def change
    add_column :jobs, :active_job_id, :string
  end
end
