class ApplicationJob < ActiveJob::Base
  def create_job_record(name)
    delayed_job = Delayed::Job.find(self.provider_job_id)
    Job.create({name: name, dictionary_id: self.arguments[0].id, active_job_id: self.job_id, delayed_job_id: delayed_job.id,
                registered_at: delayed_job.created_at})
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
    if @job.nil?
      sleep(0.1)
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
end
