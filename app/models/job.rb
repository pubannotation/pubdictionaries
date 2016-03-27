class Job < ActiveRecord::Base
  belongs_to :dictionary
  belongs_to :delayed_job
  attr_accessible :name, :num_dones, :num_items, :dictionary_id, :delayed_job_id, :message

  scope :waiting, -> {where('begun_at IS NULL')}
  scope :running, -> {where('begun_at IS NOT NULL AND ended_at IS NULL')}
  scope :unfinished, -> {where('ended_at IS NULL')}
  scope :finished, -> {where('ended_at IS NOT NULL')}

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
