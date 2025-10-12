class ApplicationJob < ActiveJob::Base
  def create_job_record(name)
    Job.create({name: name, queue_name: self.queue_name, dictionary_id: self.arguments[0].id, active_job_id: self.job_id, registered_at: Time.current})
  end

  rescue_from(StandardError) do |exception|
    if @job
      # message = "'#{exception.message}'\n#{exception.backtrace.join("\n")}"
      @job.update(message: exception.message, ended_at: Time.now)
      @job.clear_suspend_flag  # Clean up suspend file on error
    else
      raise exception
    end
  end

  private

  def set_job(active_job)
    @job = Job.find_by(active_job_id: active_job.job_id)
    count = 0
    while @job.nil?
      count += 1
      break if count > 5
      sleep(0.1)
      ActiveRecord::Base.connection.clear_query_cache
      @job = Job.find_by(active_job_id: active_job.job_id)
    end
    raise "Could not find its job object" if @job.nil?
  end

  def set_begun_at
    @job&.update_attribute(:begun_at, Time.now)
  end

  def set_ended_at
    ActiveRecord::Base.connection_pool.with_connection do
      @job&.update_attribute(:ended_at, Time.now)
      @job&.clear_suspend_flag  # Clean up suspend file when job finishes
    end
  end

  def check_suspend_flag
    if suspended?
      raise Exceptions::JobSuspendError
    end
  end

  def suspended?
    @job&.suspended?
  end

  def destroy_job_record
    @job&.destroy
  end

  def prepare_progress_record(count_scheduled)
    ActiveRecord::Base.connection_pool.with_connection do
      @job&.update_attribute(:num_items, count_scheduled)
      @job&.update_attribute(:num_dones, 0)
    end
  end

  def update_progress_record(count_completed)
    ActiveRecord::Base.connection_pool.with_connection do
      @job&.update_attribute(:num_dones, count_completed)
    end
  end

end
