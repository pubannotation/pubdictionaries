if ActiveRecord::Base.connection.table_exists?('delayed_jobs')
	CleanFilesJob.schedule!
end