module StateManagement
	def before(delayed_job)
		@job = Job.find_by_delayed_job_id(delayed_job.id)
		@job.update_attribute(:begun_at, Time.now)
	end

	def after
		@job.update_attribute(:ended_at, Time.now)
	end

  def error(job, exception)
		@job.message = "'" + exception.message + "'\n" + exception.backtrace.join("\n")
  end
end
