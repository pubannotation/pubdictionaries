class ApplicationJob < ActiveJob::Base
  def create_job_record(name)
    Job.create({name: name, queue_name: self.queue_name, dictionary_id: self.arguments[0].id, active_job_id: self.job_id, registered_at: Time.current})
  end

  rescue_from(StandardError) do |exception|
    if @job
      message = "'#{exception.message}'\n#{exception.backtrace.join("\n")}"
      @job.update(message: message, ended_at: Time.now)
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
    @job.update_attribute(:begun_at, Time.now)
  end

  def set_ended_at
    @job.update_attribute(:ended_at, Time.now)
  end

  def destroy_job_record
    @job.destroy
  end
end
