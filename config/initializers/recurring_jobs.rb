if ActiveRecord::Base.connection.data_source_exists?('delayed_jobs')
	CleanFilesJob.schedule!
end