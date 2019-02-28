class Job < ApplicationRecord
  belongs_to :dictionary

  scope :waiting, -> {where('begun_at IS NULL')}
  scope :running, -> {where('begun_at IS NOT NULL AND ended_at IS NULL')}
  scope :unfinished, -> {where('ended_at IS NULL')}
  scope :finished, -> {where('ended_at IS NOT NULL')}

  def self.time_for_tasks_to_go(queue_name)
    Job.joins("JOIN delayed_jobs on jobs.delayed_job_id = delayed_jobs.id").where('delayed_jobs.queue' => queue_name, begun_at: nil).sum(:time)
  end

  def self.number_of_tasks_to_go(queue_name)
    Delayed::Job.where(queue: queue_name, attempts: 0).count
  end

  def running?
    !begun_at.nil? && ended_at.nil?
  end

  def finished?
    !ended_at.nil?
  end

  def destroy_if_not_running
    unless running?
      dj = begin
        Delayed::Job.find(self.delayed_job_id)
      rescue
        nil
      end
      update_attribute(:delayed_job_id, nil)
      dj.delete unless dj.nil?

      update_attribute(:begun_at, Time.now)
      self.destroy
    end
  end

  def scan
    dj = begin
      Delayed::Job.find(self.delayed_job_id)
    rescue
      nil
    end
    @job.update_attribute(:ended_at, Time.now) if dj.nil?
  end

  def stop
    if running?
      dj = begin
        Delayed::Job.find(self.delayed_job_id)
      rescue
        nil
      end
      /pid:(<pid>\d+)/ =~ dj.locked_by
      # TODO
    end
  end
end
