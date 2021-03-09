class AddQueueNameColumnToJobs < ActiveRecord::Migration[6.1]
  def change
    add_column :jobs, :queue_name, :string
  end
end
