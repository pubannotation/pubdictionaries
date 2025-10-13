class AddMetadataToJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :jobs, :metadata, :jsonb
  end
end
