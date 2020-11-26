module StateManagement
	def before(delayed_job)
		@job = Job.find_by_delayed_job_id(delayed_job.id)
		if @job.nil?
			sleep(0.1)
			@job = Job.find_by_delayed_job_id(delayed_job.id)
		end
		raise "Could not find its job object" if @job.nil?

		@job.update_attribute(:begun_at, Time.now)
	end

	def after
		@job.update_attribute(:ended_at, Time.now)
	end

	def error(job, exception)
		if @job
			@job.message = "'" + exception.message + "'\n" + exception.backtrace.join("\n")
		else
			raise exception
		end
	end
end
