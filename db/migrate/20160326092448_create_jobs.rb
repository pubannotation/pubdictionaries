class CreateJobs < ActiveRecord::Migration
  def change
    create_table :jobs do |t|
    	t.string :name
      t.references :dictionary
      t.references :delayed_job
      t.text :message
      t.integer :num_items
      t.integer :num_dones
	    t.datetime :begun_at
	    t.datetime :ended_at
	    t.datetime :registered_at
    end
    add_index :jobs, :dictionary_id
    add_index :jobs, :delayed_job_id
  end
end
